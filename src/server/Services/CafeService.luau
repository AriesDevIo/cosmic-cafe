--!strict
-- The cafe loop for the world a player is standing in.
--
--   Cook:   tap a station (ProximityPrompt) to cook one serving; a Barista
--           keeps every station cooking. Servings pile up on the station tray.
--   Queue:  customers (R15 avatars, Cafe/Npc) walk in from the CustomerSpawn
--           and line up at the counter (or the first station on a fresh lot)
--           with a speech bubble showing their order.
--   Serve:  tap a customer (or let a Waiter do it) to sell everything ready of
--           their dish. Tips depend on who they are (people, rare VIP aliens,
--           the Golden Alien) and serving by hand builds a tip streak.
--   Eat:    served customers walk to a free seat, sit, eat for a few seconds
--           and leave a cash stack on the table (takeaway at the counter when
--           every seat is taken). Seated customers tip more.
--   Collect: walk over / tap a cash stack to bank it; Waiters and Managers
--           collect automatically.
--
-- Everything is server-authoritative; clients only render attributes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)
local Outfits = require(Shared.Config.Outfits)
local Progression = require(Shared.Util.Progression)
local Signal = require(Shared.Util.Signal)
local Stats = require(Shared.Util.Stats)
local Worlds = require(Shared.Config.Worlds)

local Mechanics = require(script.Parent.Parent.Mechanics)
local Npc = require(script.Parent.Parent.Cafe.Npc)
local BuildService = require(script.Parent.BuildService)
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

type CustomerState = "arriving" | "queued" | "served" | "leaving"

type Customer = {
	id: number,
	speciesId: string?, -- Codex species (VIP aliens, Golden Alien, Food Critic); nil = a regular person
	order: string,
	npc: Npc.Npc,
	prompt: ProximityPrompt,
	golden: boolean,
	critic: boolean,
	state: CustomerState,
	patienceEnd: number,
	alive: boolean,
	seat: Seat?, -- reserved when served
	pendingCash: number, -- earned but not yet on a table (banked on teardown)
}

type CashStack = {
	model: Model,
	base: BasePart,
	value: number,
	layers: number,
}

type Cafe = {
	player: Player,
	worldId: string,
	plot: Plot,
	mechanic: Mechanics.Mechanic,
	stations: { [string]: Station },
	customers: { [number]: Customer },
	queue: { Customer },
	reserved: { [Seat]: Customer },
	cash: { [Instance]: CashStack }, -- keyed by the table (or counter) it sits on
	nextSpawn: number,
	nextAutoServe: number,
	streak: number,
	lastServe: number,
	criticQueued: boolean,
	folder: Folder,
	random: Random,
}

local CafeService = {}

-- (player, reward) when a player serves the daily Food Critic.
CafeService.criticServed = Signal.new() :: Signal.Signal<Player, number>

local CAFE = Economy.cafe
local ATTR = Map.attributes
local STATION_ATTRIBUTES = { "Level", "Ready", "TrayCapacity", "Cooking", "CookEnd", "CookTime", "Auto", ATTR.Owner }
local CASH_COLOR = Color3.fromRGB(80, 200, 90)
local FOOD_LIFT = 0.25 -- studs above a table top
local MAX_CUSTOMER_LIFETIME = 240 -- seconds; a stuck NPC is removed after this

local cafes: { [Player]: Cafe } = {}
local customerFolder: Folder
local nextCustomerId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Geometry ---------------------------------------------------------------------------

-- Half the size of a part measured along a world direction.
local function halfExtent(part: BasePart, direction: Vector3): number
	local cf, size = part.CFrame, part.Size
	return math.abs(cf.RightVector:Dot(direction)) * size.X / 2
		+ math.abs(cf.UpVector:Dot(direction)) * size.Y / 2
		+ math.abs(cf.LookVector:Dot(direction)) * size.Z / 2
end

-- Toward the street (lot space +Z).
local function frontOf(cafe: Cafe): Vector3
	return cafe.plot.cframe:VectorToWorldSpace(Vector3.new(0, 0, 1))
end

local function ground(cafe: Cafe, position: Vector3): Vector3
	return Vector3.new(position.X, cafe.plot.cframe.Position.Y + 3, position.Z)
end

-- What customers line up at: the counter, or the first station on a fresh lot.
local function queueAnchor(cafe: Cafe): BasePart?
	if #cafe.plot.counters > 0 then
		return cafe.plot.counters[1]
	end
	for _, dishId in Worlds.byId[cafe.worldId].dishes do
		local station = cafe.stations[dishId]
		if station then
			return station.part
		end
	end
	return nil
end

local function queuePosition(cafe: Cafe, index: number): Vector3?
	local anchor = queueAnchor(cafe)
	if anchor == nil then
		return nil
	end
	local front = frontOf(cafe)
	local distance = halfExtent(anchor, front) + CAFE.queueGap + (index - 1) * CAFE.queueSpacing
	return ground(cafe, anchor.Position + front * distance)
end

local function nearestTable(cafe: Cafe, position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, tablePart in cafe.plot.tables do
		local distance = (tablePart.Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = tablePart, distance
		end
	end
	return best
end

-- A spot on top of `surface`, pulled toward `toward`.
local function spotOn(surface: BasePart, toward: Vector3): Vector3
	local top = surface.Position.Y + halfExtent(surface, Vector3.yAxis) + FOOD_LIFT
	local flat = surface.Position:Lerp(toward, 0.35)
	return Vector3.new(flat.X, top, flat.Z)
end

-- Stations ----------------------------------------------------------------------------

local function syncStation(cafe: Cafe, station: Station)
	local profile = DataService.get(cafe.player)
	if profile == nil then
		return
	end
	local level = Stats.dishLevel(profile, station.dishId)
	local auto = Stats.hasAutoCook(profile, cafe.worldId)
	local part = station.part
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

local function removeStation(cafe: Cafe, station: Station)
	cafe.stations[station.dishId] = nil
	station.prompt:Destroy()
	CollectionService:RemoveTag(station.part, Map.tags.ActiveStation)
	for _, name in STATION_ATTRIBUTES do
		station.part:SetAttribute(name, nil)
	end
end

-- Matches cafe.stations to the plot's stations (they appear as they're built).
local function syncStations(cafe: Cafe)
	for dishId, station in cafe.stations do
		if cafe.plot.stations[dishId] ~= station.part then
			removeStation(cafe, station)
		end
	end
	for dishId, part in cafe.plot.stations do
		if cafe.stations[dishId] then
			continue
		end
		local dish = Dishes.byId[dishId]
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CookPrompt"
		prompt.ActionText = "Cook"
		prompt.ObjectText = dish.displayName
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
		part:SetAttribute("Dish", dishId)
		CollectionService:AddTag(part, Map.tags.ActiveStation)
		prompt.Triggered:Connect(function(triggeringPlayer)
			if cafe.stations[dishId] == station then
				onCookPrompt(cafe, station, triggeringPlayer)
			end
		end)
		syncStation(cafe, station)
	end
end

-- Cash stacks ------------------------------------------------------------------------------

local function collectCash(cafe: Cafe, key: Instance, auto: boolean)
	local stack = cafe.cash[key]
	if stack == nil or cafes[cafe.player] ~= cafe then
		return
	end
	cafe.cash[key] = nil
	local profile = DataService.get(cafe.player)
	EconomyService.earn(cafe.player, stack.value)
	if profile then
		profile.stats.cashCollected += 1
		StateService.markDirty(cafe.player)
	end
	Net.fire(cafe.player, "Effect", "Cash", { position = stack.base.Position, amount = stack.value, auto = auto })
	stack.model:Destroy()
end

local function addLayer(stack: CashStack)
	if stack.layers >= CAFE.cashStackMaxValueParts then
		return
	end
	stack.layers += 1
	local bill = Instance.new("Part")
	bill.Name = "Bills" .. stack.layers
	bill.Size = Vector3.new(1.4, 0.22, 0.8)
	bill.Color = CASH_COLOR:Lerp(Color3.new(1, 1, 1), (stack.layers % 2) * 0.15)
	bill.Material = Enum.Material.SmoothPlastic
	bill.Anchored = true
	bill.CanCollide = false
	bill.CFrame = stack.base.CFrame
		* CFrame.new(0, stack.layers * 0.22, 0)
		* CFrame.Angles(0, math.rad((stack.layers * 23) % 40 - 20), 0)
	bill.Parent = stack.model
end

-- Puts (or adds to) a cash stack on `key` at `position`.
local function depositCash(cafe: Cafe, key: Instance, position: Vector3, amount: number)
	if amount <= 0 then
		return
	end
	local existing = cafe.cash[key]
	if existing then
		existing.value += amount
		existing.model:SetAttribute("Value", existing.value)
		addLayer(existing)
		return
	end
	local model = Instance.new("Model")
	model.Name = "CashStack"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.2, 0.3, 2.2)
	base.Transparency = 1
	base.Anchored = true
	base.CanCollide = false
	base.CFrame = CFrame.new(position)
	base.Parent = model
	model.PrimaryPart = base
	local stack: CashStack = { model = model, base = base, value = amount, layers = 0 }
	addLayer(stack)
	model:SetAttribute("Value", amount)
	model:SetAttribute(ATTR.Owner, cafe.player.UserId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Cash"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Map.prompt.maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	prompt.Triggered:Connect(function(player)
		if player == cafe.player then
			collectCash(cafe, key, false)
		end
	end)
	-- walking over it collects too (a bigger invisible touch zone)
	local zone = Instance.new("Part")
	zone.Name = "TouchZone"
	zone.Size = Vector3.new(4, 6, 4)
	zone.Transparency = 1
	zone.Anchored = true
	zone.CanCollide = false
	zone.CFrame = base.CFrame
	zone.Parent = model
	zone.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if character and Players:GetPlayerFromCharacter(character) == cafe.player then
			collectCash(cafe, key, false)
		end
	end)

	model.Parent = cafe.folder
	CollectionService:AddTag(model, Map.tags.CashStack)
	cafe.cash[key] = stack

	local profile = DataService.get(cafe.player)
	if profile and Stats.hasAutoCollect(profile, cafe.worldId, StateService.context(cafe.player)) then
		task.delay(CAFE.autoCollectDelay, function()
			collectCash(cafe, key, true)
		end)
	end
end

-- Customers --------------------------------------------------------------------------------

local function indexInQueue(cafe: Cafe, customer: Customer): number?
	return table.find(cafe.queue, customer)
end

local function leaveQueue(cafe: Cafe, customer: Customer)
	local index = indexInQueue(cafe, customer)
	if index then
		table.remove(cafe.queue, index)
	end
end

local function destroyCustomer(cafe: Cafe, customer: Customer)
	customer.alive = false
	cafe.customers[customer.id] = nil
	leaveQueue(cafe, customer)
	local seat = customer.seat
	if seat and cafe.reserved[seat] == customer then
		cafe.reserved[seat] = nil
	end
	customer.npc.model:Destroy()
end

local function freeSeat(cafe: Cafe): Seat?
	local free = {}
	for _, seat in cafe.plot.seats do
		if seat.Parent and seat.Occupant == nil and cafe.reserved[seat] == nil then
			table.insert(free, seat)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[cafe.random:NextInteger(1, #free)]
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

-- Who walks in: the queued critic, the Golden Alien, a VIP alien or a person.
local function pickVisitor(cafe: Cafe, profile: any): (string?, boolean)
	if cafe.criticQueued then
		cafe.criticQueued = false
		return Customers.criticId, false
	end
	if cafe.random:NextNumber() < Stats.goldenChance(profile) then
		return Customers.goldenId, true
	end
	local world = Worlds.byId[cafe.worldId]
	if #world.customers > 0 and cafe.random:NextNumber() < Customers.vipAlienChance then
		local weights: { [string]: number } = {}
		for _, speciesId in world.customers do
			weights[speciesId] = Customers.rarities[Customers.byId[speciesId].rarity].weight
		end
		return Formula.weightedPick(weights, cafe.random:NextNumber()), false
	end
	return nil, false
end

local function walkOut(cafe: Cafe, customer: Customer)
	local spawnPart: BasePart? = cafe.plot.spawns[1]
	local model = customer.npc.model
	if spawnPart and model:IsDescendantOf(workspace) then
		Npc.walkTo(customer.npc, ground(cafe, spawnPart.Position), function()
			return model:IsDescendantOf(workspace)
		end)
	end
	destroyCustomer(cafe, customer)
end

local function placeFood(cafe: Cafe, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Food"
	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Shape = Enum.PartType.Cylinder
	plate.Size = Vector3.new(0.2, 1.6, 1.6)
	plate.Color = Color3.new(1, 1, 1)
	plate.Anchored = true
	plate.CanCollide = false
	plate.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	plate.Parent = model
	local food = Instance.new("Part")
	food.Name = "Dish"
	food.Shape = Enum.PartType.Ball
	food.Size = Vector3.new(0.9, 0.9, 0.9)
	food.Color = Worlds.byId[cafe.worldId].color
	food.Anchored = true
	food.CanCollide = false
	food.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
	food.Parent = model
	model.Parent = cafe.folder
	return model
end

-- Eat (seated at a table), then leave the cash and walk out.
local function afterServe(cafe: Cafe, customer: Customer, alive: () -> boolean)
	local seat = customer.seat
	local tablePart = if seat then nearestTable(cafe, seat.Position) else nil
	if seat and tablePart then
		local away = seat.Position - tablePart.Position
		local approach = seat.Position + (if away.Magnitude > 0.01 then away.Unit * 2 else Vector3.zero)
		Npc.walkTo(customer.npc, ground(cafe, approach), alive)
		if not alive() then
			return
		end
		Npc.sit(customer.npc, seat)
		local foodSpot = spotOn(tablePart, seat.Position)
		local food = placeFood(cafe, foodSpot)
		customer.npc.model:SetAttribute("Eating", true)
		task.wait(cafe.random:NextNumber(CAFE.eatSecondsMin, CAFE.eatSecondsMax))
		food:Destroy()
		if not alive() then
			return
		end
		customer.npc.model:SetAttribute("Eating", false)
		Npc.stand(customer.npc)
		cafe.reserved[seat] = nil
		customer.seat = nil
		depositCash(cafe, tablePart, foodSpot, customer.pendingCash)
		customer.pendingCash = 0
	else
		-- takeaway: pay at the counter
		local anchor = queueAnchor(cafe)
		if anchor then
			depositCash(cafe, anchor, spotOn(anchor, anchor.Position + frontOf(cafe) * 4), customer.pendingCash)
			customer.pendingCash = 0
		end
	end
	customer.state = "leaving"
	walkOut(cafe, customer)
end

local function setQueued(customer: Customer, patience: number)
	customer.state = "queued"
	customer.patienceEnd = now() + patience
	customer.npc.model:SetAttribute("Queued", true)
	customer.npc.model:SetAttribute("PatienceEnd", customer.patienceEnd)
	customer.prompt.Enabled = true
end

local function isWaiting(customer: Customer): boolean
	return customer.state == "arriving" or customer.state == "queued"
end

-- One coroutine per customer: walk in, wait in line, then eat or give up.
local function run(cafe: Cafe, customer: Customer, patience: number)
	local born = now()
	local function alive(): boolean
		return customer.alive and cafes[cafe.player] == cafe and now() - born < MAX_CUSTOMER_LIFETIME
	end
	while alive() and isWaiting(customer) do
		local index = indexInQueue(cafe, customer)
		local spot = if index then queuePosition(cafe, index) else nil
		if spot == nil then
			break
		end
		local here = customer.npc.root.Position
		if (Vector3.new(here.X, spot.Y, here.Z) - spot).Magnitude > 1.5 then
			Npc.walkTo(customer.npc, spot, function()
				return alive() and isWaiting(customer)
			end)
			local anchor = queueAnchor(cafe)
			if anchor and isWaiting(customer) then
				Npc.face(customer.npc, anchor.Position)
			end
		end
		if customer.state == "arriving" then
			setQueued(customer, patience)
		end
		if customer.state == "queued" and now() >= customer.patienceEnd then
			-- gave up waiting
			customer.state = "leaving"
			customer.prompt.Enabled = false
			customer.npc.model:SetAttribute("Queued", false)
			customer.npc.model:SetAttribute("Leaving", true)
			leaveQueue(cafe, customer)
			walkOut(cafe, customer)
			return
		end
		task.wait(0.25)
	end
	if customer.state == "served" and alive() then
		afterServe(cafe, customer, alive)
		return
	end
	if customer.alive then
		destroyCustomer(cafe, customer)
	end
end

local serve: (cafe: Cafe, customer: Customer, manual: boolean) -> boolean

local function spawnCustomer(cafe: Cafe)
	local profile = DataService.get(cafe.player)
	local spawnPart: BasePart? = cafe.plot.spawns[1]
	if profile == nil or spawnPart == nil or queueAnchor(cafe) == nil then
		return
	end
	local order = pickOrder(cafe, profile)
	if order == nil then
		return
	end
	local speciesId, golden = pickVisitor(cafe, profile)
	local critic = speciesId == Customers.criticId
	local species = if speciesId then Customers.byId[speciesId] else nil

	local preset = if critic then Outfits.critic else nil
	local tint = if species and not critic then species.color else nil
	local npc = Npc.create(preset, tint, golden, cafe.random)
	local model = npc.model
	local start = ground(cafe, spawnPart.Position)
	model:PivotTo(CFrame.lookAt(start, start - frontOf(cafe)))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Serve"
	prompt.ObjectText = if species then species.displayName else "Customer"
	prompt.HoldDuration = Map.prompt.holdDuration
	prompt.MaxActivationDistance = Map.prompt.maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = npc.root

	nextCustomerId += 1
	local customer: Customer = {
		id = nextCustomerId,
		speciesId = speciesId,
		order = order,
		npc = npc,
		prompt = prompt,
		golden = golden,
		critic = critic,
		state = "arriving",
		patienceEnd = 0,
		alive = true,
		seat = nil,
		pendingCash = 0,
	}
	model:SetAttribute("Order", order)
	model:SetAttribute("Species", speciesId)
	model:SetAttribute("VIP", species ~= nil and not critic)
	model:SetAttribute("Golden", golden)
	model:SetAttribute("Critic", critic)
	model:SetAttribute(ATTR.Owner, cafe.player.UserId)
	model.Parent = cafe.folder
	Npc.activate(npc)
	CollectionService:AddTag(model, Map.tags.Customer)
	cafe.customers[customer.id] = customer
	table.insert(cafe.queue, customer)

	prompt.Triggered:Connect(function(player)
		if player ~= cafe.player then
			Net.fire(player, "Notify", "This is " .. cafe.player.DisplayName .. "'s customer!", "error")
			return
		end
		serve(cafe, customer, true)
	end)

	local patience = if critic then Economy.daily.criticPatience else CAFE.customerPatience
	task.spawn(run, cafe, customer, patience)
	if golden then
		Net.fire(cafe.player, "Effect", "Golden", { position = npc.root.Position })
	end
end

serve = function(cafe: Cafe, customer: Customer, manual: boolean): boolean
	if customer.state ~= "queued" or not customer.alive then
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
			Net.fire(player, "Notify", dish.displayName .. " isn't ready, cook it first!", "error")
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

	local seat = freeSeat(cafe)
	local baseTip = if customer.speciesId
		then Stats.tipMultiplier(profile, customer.speciesId)
		else Stats.humanTip(profile)
	local tip = baseTip
		* cafe.mechanic.serveMultiplier(customer.order, customer.order)
		* (if seat then CAFE.seatedTipMultiplier else 1)
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
		CafeService.criticServed:fire(player, amount)
	end
	Progression.countServe(profile)
	StateService.markDirty(player)
	if customer.speciesId then
		CodexService.recordServe(player, customer.speciesId, amount)
	end

	customer.state = "served"
	customer.pendingCash = amount
	customer.seat = seat
	if seat then
		cafe.reserved[seat] = customer
	end
	customer.prompt.Enabled = false
	customer.npc.model:SetAttribute("Queued", false)
	customer.npc.model:SetAttribute("Served", true)
	leaveQueue(cafe, customer)

	Net.fire(player, "Effect", "Serve", {
		position = customer.npc.root.Position,
		amount = amount,
		streak = if manual then cafe.streak else 0,
		multiplier = streakMultiplier,
		golden = customer.golden,
		portions = portions,
	})
	return true
end

-- Setup / teardown --------------------------------------------------------------------

local function teardown(player: Player)
	local cafe = cafes[player]
	if cafe == nil then
		return
	end
	cafes[player] = nil
	-- bank anything that was earned but not collected yet
	local owed = 0
	for _, stack in cafe.cash do
		owed += stack.value
	end
	for _, customer in cafe.customers do
		owed += customer.pendingCash
		customer.alive = false
	end
	if owed > 0 then
		local profile = DataService.get(player)
		if profile then
			Progression.earn(profile, owed)
			StateService.markDirty(player, "money")
		end
	end
	for _, station in cafe.stations do
		station.prompt:Destroy()
		for _, name in STATION_ATTRIBUTES do
			station.part:SetAttribute(name, nil)
		end
		CollectionService:RemoveTag(station.part, Map.tags.ActiveStation)
	end
	cafe.folder:Destroy() -- customers, food and cash live in here
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
		queue = {},
		reserved = {},
		cash = {},
		nextSpawn = now() + 1,
		nextAutoServe = 0,
		streak = 0,
		lastServe = -math.huge,
		criticQueued = false,
		folder = folder,
		random = Random.new(),
	}
	cafes[player] = cafe
	syncStations(cafe)
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

	local world = Worlds.byId[cafe.worldId]
	if t >= cafe.nextSpawn and #cafe.queue < world.maxCustomers then
		spawnCustomer(cafe)
		cafe.nextSpawn = t + world.spawnInterval
	end

	local ctx = StateService.context(cafe.player)
	-- Waiter / Auto-Serve pass: the first customer in line whose dish is ready.
	local interval = Stats.serveInterval(profile, cafe.worldId, ctx)
	if interval and t >= cafe.nextAutoServe then
		for _, customer in cafe.queue do
			local station = cafe.stations[customer.order]
			if customer.state == "queued" and station and station.tray > 0 then
				if serve(cafe, customer, false) then
					cafe.nextAutoServe = t + interval
				end
				break
			end
		end
	end

	-- Staff hired after cash was left on the tables: pick it up now.
	if next(cafe.cash) and Stats.hasAutoCollect(profile, cafe.worldId, ctx) then
		for key in cafe.cash do
			collectCash(cafe, key, true)
		end
	end
end

-- API ----------------------------------------------------------------------------------

-- Re-reads stations/levels/staff after a build, purchase, hire or assignment.
function CafeService.refresh(player: Player)
	local cafe = cafes[player]
	if cafe then
		syncStations(cafe)
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
	Npc.prewarm()

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
	BuildService.built:connect(function(player)
		CafeService.refresh(player)
	end)
	EconomyService.dishChanged:connect(function(player)
		CafeService.refresh(player)
	end)
	MonetizationService.changed:connect(function(player)
		CafeService.refresh(player)
	end)
	-- banks uncollected cash before the final save
	DataService.releasing:connect(teardown)
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
