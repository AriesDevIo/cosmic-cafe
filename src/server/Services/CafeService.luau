--!strict
-- The cafe loop for the world a player is standing in.
--
--   Cook:  tap a station (ProximityPrompt) to cook one serving; a Barista
--          keeps every station cooking. Servings pile up on the station's tray.
--   Serve: aliens walk in and order a dish; tap them (or let a Waiter do it)
--          to sell everything ready of that dish. Tips depend on the species,
--          and serving by hand quickly builds a tip streak (up to 2.5x).
--
-- Stations and customers carry attributes the client renders (progress bars,
-- order bubbles); the server never trusts the client about any of it.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Stats = require(Shared.Util.Stats)
local Worlds = require(Shared.Config.Worlds)

local Mechanics = require(script.Parent.Parent.Mechanics)
local CodexService = require(script.Parent.CodexService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

type Plot = WorldService.Plot

type Station = {
	dishId: string,
	part: BasePart,
	prompt: ProximityPrompt,
	cooking: boolean,
	cookEnd: number,
	tray: number,
}

type Customer = {
	id: number,
	species: string,
	order: string,
	model: Model,
	root: BasePart,
	prompt: ProximityPrompt,
	spot: BasePart,
	patienceEnd: number,
	golden: boolean,
	critic: boolean,
	arrived: boolean,
	leaving: boolean,
}

type Cafe = {
	player: Player,
	worldId: string,
	plot: Plot,
	mechanic: Mechanics.Mechanic,
	stations: { [string]: Station },
	customers: { [number]: Customer },
	nextSpawn: number,
	nextAutoServe: number,
	streak: number,
	lastServe: number,
	criticQueued: boolean,
	connections: { RBXScriptConnection },
	folder: Folder,
	random: Random,
}

local CafeService = {}

-- (player, reward) when a player serves the daily Food Critic.
CafeService.criticServed = Signal.new() :: Signal.Signal<Player, number>

local CAFE = Economy.cafe
local ATTR = Map.attributes

local cafes: { [Player]: Cafe } = {}
local customerFolder: Folder
local nextCustomerId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Station helpers -------------------------------------------------------------------

local function syncStation(cafe: Cafe, station: Station)
	local profile = DataService.get(cafe.player)
	if profile == nil then
		return
	end
	local level = Stats.dishLevel(profile, station.dishId)
	local auto = Stats.hasAutoCook(profile, cafe.worldId)
	local part = station.part
	part:SetAttribute("Dish", station.dishId) -- mirrored for Model stations
	part:SetAttribute("Level", level)
	part:SetAttribute("Ready", station.tray)
	part:SetAttribute("TrayCapacity", CAFE.trayCapacity)
	part:SetAttribute("Cooking", station.cooking)
	part:SetAttribute("CookEnd", station.cookEnd)
	part:SetAttribute("CookTime", if level > 0 then Stats.cookTime(profile, station.dishId) else 0)
	part:SetAttribute("Auto", auto)
	part:SetAttribute(ATTR.Owner, cafe.player.UserId)
	station.prompt.Enabled = level > 0 and not auto
end

local function startCooking(cafe: Cafe, station: Station, from: number)
	local profile = DataService.get(cafe.player)
	if profile == nil then
		return
	end
	station.cooking = true
	station.cookEnd = from + Stats.cookTime(profile, station.dishId)
end

local function onCookPrompt(cafe: Cafe, station: Station, player: Player)
	if player ~= cafe.player then
		Net.fire(player, "Notify", "This is " .. cafe.player.DisplayName .. "'s cafe!", "error")
		return
	end
	local profile = DataService.get(player)
	if profile == nil or Stats.dishLevel(profile, station.dishId) <= 0 or station.cooking then
		return
	end
	if station.tray >= CAFE.trayCapacity then
		Net.fire(player, "Notify", "Tray is full, serve some customers!", "error")
		return
	end
	startCooking(cafe, station, now())
	syncStation(cafe, station)
	Net.fire(player, "Effect", "Cook", { dish = station.dishId })
end

-- Customers -------------------------------------------------------------------------

local function weld(part: BasePart, root: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = part
end

local function buildCustomerModel(species: Customers.Species, golden: boolean): (Model, BasePart)
	local sizes = Map.customer
	local model = Instance.new("Model")
	model.Name = species.displayName
	local color = if golden then Color3.fromRGB(255, 215, 0) else species.color
	local material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = sizes.rootSize
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local function piece(name: string, size: Vector3, offset: Vector3, shape: Enum.PartType, pieceColor: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.Color = pieceColor
		part.Material = material
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.Anchored = false
		part.CFrame = root.CFrame * CFrame.new(offset)
		part.Parent = model
		weld(part, root)
		return part
	end

	local bodyY = sizes.bodySize.Y / 2
	piece("Body", sizes.bodySize, Vector3.new(0, bodyY - sizes.rootSize.Y / 2, 0), Enum.PartType.Block, color)
	local headY = sizes.bodySize.Y + sizes.headSize.Y / 2 - sizes.rootSize.Y / 2
	piece("Head", sizes.headSize, Vector3.new(0, headY, 0), Enum.PartType.Ball, color)
	local eye = sizes.eyeSize
	piece("EyeL", eye, Vector3.new(-0.45, headY + 0.2, -1.05), Enum.PartType.Ball, Color3.new(0, 0, 0))
	piece("EyeR", eye, Vector3.new(0.45, headY + 0.2, -1.05), Enum.PartType.Ball, Color3.new(0, 0, 0))
	local antenna = piece(
		"Antenna",
		sizes.antennaSize,
		Vector3.new(0, headY + (sizes.headSize.Y + sizes.antennaSize.Y) / 2, 0),
		Enum.PartType.Block,
		color
	)
	antenna.Material = Enum.Material.Neon

	if golden then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Rate = sizes.goldenSparkleRate
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		sparkles.LightEmission = 1
		sparkles.Parent = root
	end
	return model, root
end

local function spotCFrame(cafe: Cafe, spot: BasePart): CFrame
	local plotY = cafe.plot.cframe.Position.Y
	local offset = cafe.plot.cframe:VectorToWorldSpace(Map.customer.standOffset)
	local position = spot.Position + offset
	position = Vector3.new(position.X, plotY + Map.customer.rootSize.Y / 2, position.Z)
	return CFrame.lookAt(position, Vector3.new(spot.Position.X, position.Y, spot.Position.Z))
end

local function freeSpot(cafe: Cafe): BasePart?
	local taken: { [BasePart]: boolean } = {}
	for _, customer in cafe.customers do
		taken[customer.spot] = true
	end
	local spots: { BasePart } = if #cafe.plot.tables > 0 then cafe.plot.tables else cafe.plot.counters
	local free = {}
	for _, spot in spots do
		if not taken[spot] and spot.Parent then
			table.insert(free, spot)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[cafe.random:NextInteger(1, #free)]
end

local function walk(root: BasePart, target: CFrame): number
	local duration = math.max((target.Position - root.Position).Magnitude / CAFE.customerWalkSpeed, 0.1)
	TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = target }):Play()
	return duration
end

local function removeCustomer(cafe: Cafe, customer: Customer)
	if customer.leaving then
		return
	end
	customer.leaving = true
	customer.prompt.Enabled = false
	customer.model:SetAttribute("Leaving", true)
	cafe.customers[customer.id] = nil
	local spawn = cafe.plot.spawns[1]
	if spawn and customer.root.Parent then
		local duration =
			walk(customer.root, CFrame.new(spawn.Position + Vector3.new(0, Map.customer.rootSize.Y / 2, 0)))
		Debris:AddItem(customer.model, duration + 0.1)
	else
		customer.model:Destroy()
	end
end

local function pickSpecies(cafe: Cafe, profile: any): (string, boolean)
	if cafe.random:NextNumber() < Stats.goldenChance(profile) then
		return Customers.goldenId, true
	end
	local world = Worlds.byId[cafe.worldId]
	local weights: { [string]: number } = {}
	for _, speciesId in world.customers do
		weights[speciesId] = Customers.rarities[Customers.byId[speciesId].rarity].weight
	end
	return Formula.weightedPick(weights, cafe.random:NextNumber()) or world.customers[1], false
end

local function pickOrder(cafe: Cafe, profile: any): string?
	local ctx = StateService.context(cafe.player)
	local weights: { [string]: number } = {}
	for dishId, station in cafe.stations do
		if Stats.dishLevel(profile, dishId) > 0 then
			local bias = if station.tray > 0 then CAFE.readyOrderBias else 1
			weights[dishId] = cafe.mechanic.orderWeight(dishId, ctx) * bias
		end
	end
	return Formula.weightedPick(weights, cafe.random:NextNumber())
end

local serve: (cafe: Cafe, customer: Customer, manual: boolean) -> boolean

local function spawnCustomer(cafe: Cafe)
	local profile = DataService.get(cafe.player)
	local spawnPart: BasePart? = cafe.plot.spawns[1]
	if profile == nil or spawnPart == nil then
		return
	end
	local spot = freeSpot(cafe)
	local order = pickOrder(cafe, profile)
	if spot == nil or order == nil then
		return
	end

	local critic = cafe.criticQueued
	local speciesId, golden
	if critic then
		cafe.criticQueued = false
		speciesId, golden = Customers.criticId, false
	else
		speciesId, golden = pickSpecies(cafe, profile)
	end
	local species = Customers.byId[speciesId]

	nextCustomerId += 1
	local model, root = buildCustomerModel(species, golden)
	local start = CFrame.new(spawnPart.Position + Vector3.new(0, Map.customer.rootSize.Y / 2, 0))
	model:PivotTo(start)
	local patience = if critic then Economy.daily.criticPatience else CAFE.customerPatience

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Serve"
	prompt.ObjectText = species.displayName
	prompt.HoldDuration = Map.prompt.holdDuration
	prompt.MaxActivationDistance = Map.prompt.maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	local customer: Customer = {
		id = nextCustomerId,
		species = speciesId,
		order = order,
		model = model,
		root = root,
		prompt = prompt,
		spot = spot,
		patienceEnd = 0,
		golden = golden,
		critic = critic,
		arrived = false,
		leaving = false,
	}
	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Order", order)
	model:SetAttribute("Golden", golden)
	model:SetAttribute("Critic", critic)
	model:SetAttribute(ATTR.Owner, cafe.player.UserId)
	model.Parent = cafe.folder
	CollectionService:AddTag(model, Map.tags.Customer)
	cafe.customers[customer.id] = customer

	prompt.Triggered:Connect(function(player)
		if player ~= cafe.player then
			Net.fire(player, "Notify", "This is " .. cafe.player.DisplayName .. "'s customer!", "error")
			return
		end
		serve(cafe, customer, true)
	end)

	local duration = walk(root, spotCFrame(cafe, spot))
	task.delay(duration, function()
		if customer.leaving or cafes[cafe.player] ~= cafe then
			return
		end
		customer.arrived = true
		customer.patienceEnd = now() + patience
		model:SetAttribute("PatienceEnd", customer.patienceEnd)
		model:SetAttribute("Arrived", true)
		prompt.Enabled = true
	end)

	if golden then
		Net.fire(cafe.player, "Effect", "Golden", { position = root.Position })
	end
end

serve = function(cafe: Cafe, customer: Customer, manual: boolean): boolean
	if customer.leaving or not customer.arrived then
		return false
	end
	local player = cafe.player
	local profile = DataService.get(player)
	local station = cafe.stations[customer.order]
	if profile == nil or station == nil then
		return false
	end
	if station.tray <= 0 then
		if manual then
			local dish = Dishes.byId[customer.order]
			Net.fire(player, "Notify", dish.icon .. " " .. dish.displayName .. " isn't ready, cook it first!", "error")
		end
		return false
	end

	local ctx = StateService.context(player)
	local portions = station.tray
	station.tray = 0
	if not station.cooking and Stats.hasAutoCook(profile, cafe.worldId) then
		startCooking(cafe, station, now())
	end
	syncStation(cafe, station)

	local tip = Stats.tipMultiplier(profile, customer.species)
		* cafe.mechanic.serveMultiplier(customer.order, customer.order)
	local streakMultiplier = 1
	if manual then
		local t = now()
		cafe.streak = if t - cafe.lastServe <= Economy.streak.window then cafe.streak + 1 else 1
		cafe.lastServe = t
		streakMultiplier = Formula.streakMultiplier(cafe.streak, Economy.streak.perServe, Economy.streak.maxMultiplier)
		profile.stats.bestStreak = math.max(profile.stats.bestStreak, cafe.streak)
		StateService.pushRuntime(player)
	end

	local amount = Stats.dishValue(profile, ctx, customer.order) * portions * tip * streakMultiplier
	if customer.critic then
		local critique = Stats.worldRate(profile, ctx, cafe.worldId) * Economy.daily.criticRewardSeconds
		amount = math.max(amount, critique)
	end
	EconomyService.earn(player, amount)
	Net.fire(player, "Effect", "Coin", {
		position = customer.root.Position,
		amount = amount,
		streak = if manual then cafe.streak else 0,
		multiplier = streakMultiplier,
		golden = customer.golden,
		portions = portions,
	})
	if customer.critic then
		CafeService.criticServed:fire(player, amount)
	end
	CodexService.recordServe(player, customer.species, amount)
	removeCustomer(cafe, customer)
	return true
end

-- Setup / teardown --------------------------------------------------------------------

local function teardown(player: Player)
	local cafe = cafes[player]
	if cafe == nil then
		return
	end
	cafes[player] = nil
	for _, connection in cafe.connections do
		connection:Disconnect()
	end
	for _, station in cafe.stations do
		station.prompt:Destroy()
		for _, name in { "Level", "Ready", "TrayCapacity", "Cooking", "CookEnd", "CookTime", "Auto", ATTR.Owner } do
			station.part:SetAttribute(name, nil)
		end
	end
	cafe.folder:Destroy() -- customers live in here
	local decor = cafe.plot.root:FindFirstChild("VIPDecor")
	if decor then
		decor:Destroy()
	end
end

local function applyDecor(player: Player, plot: Plot)
	local existing = plot.root:FindFirstChild("VIPDecor")
	if MonetizationService.owns(player, "VIPDecor") then
		if existing == nil then
			local highlight = Instance.new("Highlight")
			highlight.Name = "VIPDecor"
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(255, 215, 0)
			highlight.Parent = plot.root
		end
	elseif existing then
		existing:Destroy()
	end
end

local function setup(player: Player, worldId: string, plot: Plot)
	teardown(player)
	local world = Worlds.byId[worldId]
	local folder = Instance.new("Folder")
	folder.Name = "Cafe_" .. player.UserId
	folder.Parent = customerFolder

	local cafe: Cafe = {
		player = player,
		worldId = worldId,
		plot = plot,
		mechanic = Mechanics.get(world.mechanic),
		stations = {},
		customers = {},
		nextSpawn = now() + 1,
		nextAutoServe = 0,
		streak = 0,
		lastServe = -math.huge,
		criticQueued = false,
		connections = {},
		folder = folder,
		random = Random.new(),
	}
	for dishId, part in plot.stations do
		local dish = Dishes.byId[dishId]
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CookPrompt"
		prompt.ActionText = "Cook"
		prompt.ObjectText = dish.icon .. " " .. dish.displayName
		prompt.HoldDuration = Map.prompt.holdDuration
		prompt.MaxActivationDistance = Map.prompt.maxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		local station: Station = {
			dishId = dishId,
			part = part,
			prompt = prompt,
			cooking = false,
			cookEnd = 0,
			tray = 0,
		}
		cafe.stations[dishId] = station
		table.insert(
			cafe.connections,
			prompt.Triggered:Connect(function(triggeringPlayer)
				onCookPrompt(cafe, station, triggeringPlayer)
			end)
		)
		syncStation(cafe, station)
	end
	cafes[player] = cafe
	applyDecor(player, plot)
	StateService.pushRuntime(player)
end

-- Simulation tick ----------------------------------------------------------------------

local function tickCafe(cafe: Cafe, t: number)
	local profile = DataService.get(cafe.player)
	if profile == nil then
		return
	end
	local autoCook = Stats.hasAutoCook(profile, cafe.worldId)

	for _, station in cafe.stations do
		local changed = false
		if station.cooking and t >= station.cookEnd then
			if autoCook then
				local cookTime = Stats.cookTime(profile, station.dishId)
				local cycles = 1 + math.floor((t - station.cookEnd) / cookTime)
				cycles = math.min(cycles, CAFE.trayCapacity - station.tray)
				station.tray += math.max(cycles, 0)
				if station.tray < CAFE.trayCapacity then
					station.cookEnd += cycles * cookTime
				else
					station.cooking = false
				end
			else
				station.tray += 1
				station.cooking = false
			end
			changed = true
		end
		if autoCook and not station.cooking and station.tray < CAFE.trayCapacity then
			if Stats.dishLevel(profile, station.dishId) > 0 then
				startCooking(cafe, station, t)
				changed = true
			end
		end
		if changed then
			syncStation(cafe, station)
		end
	end

	-- Customers: impatient ones leave, new ones arrive.
	local count = 0
	for _, customer in cafe.customers do
		if customer.arrived and t >= customer.patienceEnd then
			removeCustomer(cafe, customer)
		else
			count += 1
		end
	end
	local world = Worlds.byId[cafe.worldId]
	if t >= cafe.nextSpawn and count < world.maxCustomers then
		spawnCustomer(cafe)
		cafe.nextSpawn = t + world.spawnInterval
	end

	-- Waiter / Auto-Serve pass.
	local interval = Stats.serveInterval(profile, cafe.worldId, StateService.context(cafe.player))
	if interval and t >= cafe.nextAutoServe then
		local best: Customer? = nil
		for _, customer in cafe.customers do
			local station = cafe.stations[customer.order]
			if customer.arrived and station and station.tray > 0 and (best == nil or customer.id < best.id) then
				best = customer
			end
		end
		if best and serve(cafe, best, false) then
			cafe.nextAutoServe = t + interval
		end
	end
end

-- API ----------------------------------------------------------------------------------

-- Re-reads levels/staff after a purchase, hire or assignment.
function CafeService.refresh(player: Player)
	local cafe = cafes[player]
	if cafe then
		for _, station in cafe.stations do
			syncStation(cafe, station)
		end
		applyDecor(player, cafe.plot)
	end
end

-- The next customer in this player's cafe will be the Food Critic.
function CafeService.queueCritic(player: Player)
	local cafe = cafes[player]
	if cafe then
		cafe.criticQueued = true
	end
end

function CafeService.hasCriticWaiting(player: Player): boolean
	local cafe = cafes[player]
	if cafe == nil then
		return false
	end
	if cafe.criticQueued then
		return true
	end
	for _, customer in cafe.customers do
		if customer.critic then
			return true
		end
	end
	return false
end

function CafeService.init()
	customerFolder = Instance.new("Folder")
	customerFolder.Name = "CosmicCafeCustomers"
	customerFolder.Parent = workspace

	StateService.addRuntimeProvider("cafe", function(player)
		local cafe = cafes[player]
		if cafe == nil then
			return nil
		end
		local active = now() - cafe.lastServe <= Economy.streak.window
		local streak = if active then cafe.streak else 0
		return {
			streak = streak,
			multiplier = Formula.streakMultiplier(streak, Economy.streak.perServe, Economy.streak.maxMultiplier),
			expiresAt = cafe.lastServe + Economy.streak.window,
		}
	end)
end

function CafeService.start()
	WorldService.travelled:connect(setup)
	EconomyService.dishChanged:connect(function(player)
		CafeService.refresh(player)
	end)
	MonetizationService.changed:connect(function(player)
		CafeService.refresh(player)
	end)
	Players.PlayerRemoving:Connect(teardown)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < CAFE.tickInterval then
			return
		end
		accumulator = 0
		local t = now()
		for _, cafe in cafes do
			local ok, err = pcall(function()
				tickCafe(cafe, t)
				return nil
			end)
			if not ok then
				warn("[CafeService] tick failed for " .. cafe.player.Name .. ": " .. tostring(err))
			end
		end
	end)
end

return CafeService
