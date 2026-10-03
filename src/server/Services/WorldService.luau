--!strict
-- Worlds and plots.
--
-- Everything is found through CollectionService tags + attributes (see
-- Config/Map.luau and docs/MAP_CONTRACT.md). Each player gets their own
-- CafePlot in every world they visit; if the map has no free plot (or none at
-- all) a placeholder plot is generated, and any station/counter/table/spawn a
-- plot is missing is generated too, so the game is playable on an empty
-- baseplate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Dishes = require(Shared.Config.Dishes)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Signal = require(Shared.Util.Signal)
local Validate = require(Shared.Util.Validate)
local Worlds = require(Shared.Config.Worlds)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

export type Plot = {
	id: string,
	worldId: string,
	root: Instance,
	cframe: CFrame, -- top surface of the plot, +Z = front
	stations: { [string]: BasePart },
	counters: { BasePart },
	tables: { BasePart },
	spawns: { BasePart },
	owner: Player?,
	generated: boolean,
}

local WorldService = {}

-- (player, worldId, plot) after a player arrives in a world (also on join).
WorldService.travelled = Signal.new() :: Signal.Signal<Player, string, Plot>
WorldService.unlocked = Signal.new() :: Signal.Signal<Player, string>

local TAGS = Map.tags
local ATTR = Map.attributes
local LAYOUT = Map.placeholder

local plots: { Plot } = {}
local assignments: { [Player]: { [string]: Plot } } = {}
local weatherState: { [string]: { id: string?, endsAt: number } } = {}
local generatedFolder: Folder
local plotCounter = 0

-- Geometry helpers -----------------------------------------------------------------

local function basePartOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

-- The plot's top surface CFrame.
local function surfaceOf(root: Instance): CFrame
	if root:IsA("BasePart") then
		return root.CFrame * CFrame.new(0, root.Size.Y / 2, 0)
	elseif root:IsA("Model") then
		return root:GetPivot()
	end
	return CFrame.new()
end

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function label(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlaceholderLabel"
	gui.Size = UDim2.fromOffset(160, 28)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Enum.Font.GothamBold
	text_.TextScaled = true
	text_.TextColor3 = Color3.new(1, 1, 1)
	text_.TextStrokeTransparency = 0.4
	text_.Text = text
	text_.Parent = gui
	gui.Parent = part
end

-- Plot discovery ----------------------------------------------------------------------

local function plotAncestor(instance: Instance): Instance?
	local current = instance.Parent
	while current and current ~= game do
		if CollectionService:HasTag(current, TAGS.CafePlot) then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Which plot (of `worldId`, if given) a loose map object belongs to.
local function owningPlot(instance: Instance, worldId: string?): Plot?
	local ancestor = plotAncestor(instance)
	local plotId = instance:GetAttribute(ATTR.PlotId)
	local position = positionOf(instance)
	local best: Plot? = nil
	local bestDistance = Map.plotRadius
	for _, plot in plots do
		if worldId == nil or plot.worldId == worldId then
			if ancestor and plot.root == ancestor then
				return plot
			end
			if plotId ~= nil and plot.root:GetAttribute(ATTR.PlotId) == plotId then
				return plot
			end
			if ancestor == nil and plotId == nil and position then
				local distance = (plot.cframe.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = plot, distance
				end
			end
		end
	end
	return best
end

local function registerPlot(root: Instance, generated: boolean): Plot?
	local worldId = root:GetAttribute(ATTR.World)
	if type(worldId) ~= "string" or Worlds.byId[worldId] == nil then
		warn("[WorldService] CafePlot " .. root:GetFullName() .. " has no valid World attribute")
		return nil
	end
	plotCounter += 1
	local plot: Plot = {
		id = worldId .. "#" .. plotCounter,
		worldId = worldId,
		root = root,
		cframe = surfaceOf(root),
		stations = {},
		counters = {},
		tables = {},
		spawns = {},
		owner = nil,
		generated = generated,
	}
	table.insert(plots, plot)
	return plot
end

local function indexTagged()
	for _, instance in CollectionService:GetTagged(TAGS.Station) do
		local dishId = instance:GetAttribute(ATTR.Dish)
		local dish = if type(dishId) == "string" then Dishes.byId[dishId] else nil
		local part = basePartOf(instance)
		if dish == nil or part == nil then
			warn("[WorldService] Station " .. instance:GetFullName() .. " has no valid Dish attribute")
			continue
		end
		local plot = owningPlot(instance, dish.world)
		local existing: BasePart? = if plot then plot.stations[dish.id] else nil
		if plot and existing == nil then
			plot.stations[dish.id] = part
		end
	end
	local lists = {
		{ tag = TAGS.Counter, key = "counters" },
		{ tag = TAGS.Table, key = "tables" },
		{ tag = TAGS.CustomerSpawn, key = "spawns" },
	}
	for _, entry in lists do
		for _, instance in CollectionService:GetTagged(entry.tag) do
			local part = basePartOf(instance)
			local plot = owningPlot(instance, nil)
			if part and plot then
				table.insert((plot :: any)[entry.key], part)
			end
		end
	end
end

-- Placeholders --------------------------------------------------------------------------

local function plotFolder(plot: Plot): Folder
	local name = "Plot_" .. plot.id
	local existing = generatedFolder:FindFirstChild(name)
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = generatedFolder
	return folder
end

-- Generates anything a plot is missing.
local function completePlot(plot: Plot)
	local world = Worlds.byId[plot.worldId]
	local folder: Folder? = nil
	local function parentFolder(): Folder
		folder = folder or plotFolder(plot)
		return folder :: Folder
	end

	local count = #world.dishes
	for index, dishId in world.dishes do
		local existing: BasePart? = plot.stations[dishId]
		if existing == nil then
			local dish = Dishes.byId[dishId]
			local x = (index - (count + 1) / 2) * LAYOUT.stationSpacing
			local part = makePart({
				Name = "Station_" .. dishId,
				Size = LAYOUT.stationSize,
				CFrame = plot.cframe * CFrame.new(x, LAYOUT.stationSize.Y / 2, LAYOUT.stationRowZ),
				Color = world.color:Lerp(Color3.new(1, 1, 1), 0.35),
			})
			part:SetAttribute(ATTR.Dish, dishId)
			label(part, dish.icon .. " " .. dish.displayName)
			part.Parent = parentFolder()
			CollectionService:AddTag(part, TAGS.Station)
			plot.stations[dishId] = part
		end
	end
	if #plot.counters == 0 then
		local part = makePart({
			Name = "Counter",
			Size = LAYOUT.counterSize,
			CFrame = plot.cframe * CFrame.new(LAYOUT.counterOffset),
			Color = Color3.fromRGB(120, 80, 50),
			Material = Enum.Material.Wood,
		})
		part.Parent = parentFolder()
		CollectionService:AddTag(part, TAGS.Counter)
		table.insert(plot.counters, part)
	end
	if #plot.tables == 0 then
		for index, offset in LAYOUT.tableOffsets do
			local part = makePart({
				Name = "Table" .. index,
				Size = LAYOUT.tableSize,
				CFrame = plot.cframe * CFrame.new(offset),
				Color = Color3.fromRGB(240, 240, 240),
				Shape = Enum.PartType.Cylinder,
			})
			part.CFrame *= CFrame.Angles(0, 0, math.rad(90))
			part.Parent = parentFolder()
			CollectionService:AddTag(part, TAGS.Table)
			table.insert(plot.tables, part)
		end
	end
	if #plot.spawns == 0 then
		local part = makePart({
			Name = "CustomerSpawn",
			Size = Vector3.new(4, 1, 4),
			CFrame = plot.cframe * CFrame.new(LAYOUT.customerSpawnOffset),
			Transparency = 1,
			CanCollide = false,
		})
		part.Parent = parentFolder()
		CollectionService:AddTag(part, TAGS.CustomerSpawn)
		table.insert(plot.spawns, part)
	end
end

-- Where a new placeholder plot goes: in a row next to the world's first
-- hand-built plot, or in the world's own generated area.
local function nextPlotCFrame(worldId: string): CFrame
	local world = Worlds.byId[worldId]
	local handBuilt: Plot? = nil
	local generatedCount = 0
	for _, plot in plots do
		if plot.worldId == worldId then
			if plot.generated then
				generatedCount += 1
			elseif handBuilt == nil then
				handBuilt = plot
			end
		end
	end
	if handBuilt then
		return handBuilt.cframe * CFrame.new(LAYOUT.extraPlotSpacing * (generatedCount + 1))
	end
	local origin = LAYOUT.worldOrigin + LAYOUT.worldSpacing * (world.index - 1)
	return CFrame.new(origin + LAYOUT.plotSpacing * generatedCount)
end

local function generatePlot(worldId: string): Plot
	local world = Worlds.byId[worldId]
	local surface = nextPlotCFrame(worldId)
	local floor = makePart({
		Name = "CafePlot_" .. worldId,
		Size = LAYOUT.plotSize,
		CFrame = surface * CFrame.new(0, -LAYOUT.plotSize.Y / 2, 0),
		Color = world.color,
	})
	floor:SetAttribute(ATTR.World, worldId)
	floor.Parent = generatedFolder
	CollectionService:AddTag(floor, TAGS.CafePlot)
	local plot = registerPlot(floor, true) :: Plot
	completePlot(plot)
	return plot
end

-- Portals & gates ---------------------------------------------------------------------------

local function worldAnchor(worldId: string): Plot
	for _, plot in plots do
		if plot.worldId == worldId then
			return plot
		end
	end
	return generatePlot(worldId)
end

local function generatePortals()
	local targets: { [string]: boolean } = {}
	for _, portal in CollectionService:GetTagged(TAGS.WorldPortal) do
		local target = portal:GetAttribute(ATTR.Target)
		if type(target) == "string" then
			targets[target] = true
		end
	end
	for _, world in Worlds.list do
		if not world.enabled then
			continue
		end
		local anchor = worldAnchor(world.id)
		local slot = 0
		for _, target in Worlds.list do
			if target.enabled and target.id ~= world.id and not targets[target.id] then
				slot += 1
				local part = makePart({
					Name = "Portal_" .. target.id,
					Size = LAYOUT.portalSize,
					CFrame = anchor.cframe
						* CFrame.new(LAYOUT.portalOffsetX, LAYOUT.portalSize.Y / 2, (slot - 1) * LAYOUT.portalSpacingZ)
						* CFrame.Angles(0, math.rad(90), 0),
					Color = target.color,
					Material = Enum.Material.Neon,
					Transparency = 0.3,
					CanCollide = false,
				})
				part:SetAttribute(ATTR.Target, target.id)
				label(part, "🌀 " .. target.displayName)
				part.Parent = generatedFolder
				CollectionService:AddTag(part, TAGS.WorldPortal)
			end
		end
	end
end

-- Weather ----------------------------------------------------------------------------------

function WorldService.weather(worldId: string): string?
	local state = weatherState[worldId]
	return if state then state.id else nil
end

local function playersIn(worldId: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile and profile.currentWorld == worldId then
			table.insert(list, player)
		end
	end
	return list
end

local function runWeather(world: Worlds.World)
	local config = world.weather
	if config == nil then
		return
	end
	local random = Random.new()
	local state = { id = nil :: string?, endsAt = 0 }
	weatherState[world.id] = state
	local function publish()
		workspace:SetAttribute("Weather_" .. world.id, state.id or "")
		workspace:SetAttribute("WeatherEnds_" .. world.id, state.endsAt)
		for _, player in playersIn(world.id) do
			StateService.markDirty(player)
			StateService.pushRuntime(player)
		end
	end
	while true do
		state.id = nil
		state.endsAt = workspace:GetServerTimeNow() + config.calmSeconds
		publish()
		task.wait(config.calmSeconds)
		local weather = config.weathers[random:NextInteger(1, #config.weathers)]
		state.id = weather.id
		state.endsAt = workspace:GetServerTimeNow() + config.rushSeconds
		publish()
		for _, player in playersIn(world.id) do
			Net.fire(
				player,
				"Notify",
				string.format(
					"%s %s! %s dishes sell for %gx",
					weather.icon,
					weather.displayName,
					weather.tag,
					weather.valueMultiplier
				),
				"weather"
			)
		end
		task.wait(config.rushSeconds)
	end
end

-- Plots API ---------------------------------------------------------------------------------

function WorldService.plotFor(player: Player, worldId: string): Plot
	local mine = assignments[player]
	if mine == nil then
		mine = {}
		assignments[player] = mine
	end
	local existing = mine[worldId]
	if existing then
		return existing
	end
	local chosen: Plot? = nil
	for _, plot in plots do
		if plot.worldId == worldId and plot.owner == nil then
			chosen = plot
			break
		end
	end
	local plot = chosen or generatePlot(worldId)
	completePlot(plot)
	plot.owner = player
	plot.root:SetAttribute(ATTR.Owner, player.UserId)
	plot.root:SetAttribute("OwnerName", player.DisplayName)
	mine[worldId] = plot
	return plot
end

function WorldService.currentPlot(player: Player): Plot?
	local profile = DataService.get(player)
	local mine = assignments[player]
	if profile == nil or mine == nil then
		return nil
	end
	return mine[profile.currentWorld]
end

local function teleport(player: Player, plot: Plot)
	local character = player.Character
	if character == nil then
		return
	end
	local target = plot.cframe * CFrame.new(LAYOUT.playerSpawnOffset)
	character:PivotTo(CFrame.lookAt(target.Position, (plot.cframe * CFrame.new(0, 4, 0)).Position))
end

function WorldService.notify(player: Player, text: string, style: string?)
	Net.fire(player, "Notify", text, style or "info")
end

-- Moves the player into `worldId` (must be unlocked). Returns success.
function WorldService.travel(player: Player, worldId: string): boolean
	local profile = DataService.get(player)
	if profile == nil then
		return false
	end
	local ok, err = Progression.travel(profile, worldId)
	if not ok then
		WorldService.notify(player, err or "Can't travel there", "error")
		return false
	end
	local plot = WorldService.plotFor(player, worldId)
	teleport(player, plot)
	StateService.markDirty(player)
	WorldService.travelled:fire(player, worldId, plot)
	return true
end

function WorldService.unlock(player: Player, worldId: string): boolean
	local profile = DataService.get(player)
	if profile == nil then
		return false
	end
	local ok, err = Progression.unlockWorld(profile, worldId)
	if not ok then
		WorldService.notify(player, err or "Can't unlock", "error")
		return false
	end
	local world = Worlds.byId[worldId]
	WorldService.notify(player, "🎉 " .. world.displayName .. " unlocked!", "success")
	Net.fireAll("Announce", player.DisplayName .. " opened a cafe in " .. world.displayName .. "!", "#7FD8FF")
	StateService.markDirty(player)
	WorldService.unlocked:fire(player, worldId)
	WorldService.travel(player, worldId)
	return true
end

local function lockedMessage(worldId: string): string
	local world = Worlds.byId[worldId]
	if not world.enabled then
		return world.displayName .. " is coming soon!"
	end
	return "🔒 " .. world.displayName .. " costs " .. BigNum.money(world.unlockCost) .. " (open the Worlds menu)"
end

local function hookPortal(portal: Instance)
	local part = basePartOf(portal)
	local target = portal:GetAttribute(ATTR.Target)
	if part == nil or type(target) ~= "string" or Worlds.byId[target] == nil then
		return
	end
	local last: { [Player]: number } = {}
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if player == nil then
			return
		end
		local now = os.clock()
		if (last[player] or 0) + Map.portalCooldown > now then
			return
		end
		last[player] = now
		local profile = DataService.get(player)
		if profile == nil or profile.currentWorld == target then
			return
		end
		if profile.worlds[target].unlocked then
			WorldService.travel(player, target)
		else
			WorldService.notify(player, lockedMessage(target), "error")
		end
	end)
end

local function hookGate(gate: Instance)
	local part = basePartOf(gate)
	local worldId = gate:GetAttribute(ATTR.World)
	if part == nil or type(worldId) ~= "string" or Worlds.byId[worldId] == nil then
		return
	end
	local world = Worlds.byId[worldId]
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UnlockPrompt"
	prompt.ActionText = "Unlock " .. BigNum.money(world.unlockCost)
	prompt.ObjectText = world.displayName
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = Map.prompt.maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local profile = DataService.get(player)
		if profile and not profile.worlds[worldId].unlocked then
			WorldService.unlock(player, worldId)
		end
	end)
end

-- Lifecycle -----------------------------------------------------------------------------------

function WorldService.init()
	generatedFolder = Instance.new("Folder")
	generatedFolder.Name = "CosmicCafeGenerated"
	generatedFolder.Parent = workspace

	for _, root in CollectionService:GetTagged(TAGS.CafePlot) do
		registerPlot(root, false)
	end
	indexTagged()
	for _, plot in plots do
		completePlot(plot)
	end
	for _, world in Worlds.list do
		if world.enabled then
			worldAnchor(world.id)
		end
	end
	generatePortals()

	StateService.setWeatherProvider(WorldService.weather)
	StateService.addRuntimeProvider("weather", function()
		local values = {}
		for worldId, state in weatherState do
			values[worldId] = { id = state.id, endsAt = state.endsAt }
		end
		return values
	end)
end

function WorldService.start()
	for _, portal in CollectionService:GetTagged(TAGS.WorldPortal) do
		hookPortal(portal)
	end
	for _, gate in CollectionService:GetTagged(TAGS.UnlockGate) do
		hookGate(gate)
	end
	for _, world in Worlds.list do
		if world.enabled and world.weather then
			task.spawn(runWeather, world)
		end
	end

	DataService.loaded:connect(function(player, profile)
		local plot = WorldService.plotFor(player, profile.currentWorld)
		if player.Character then
			teleport(player, plot)
		end
		WorldService.travelled:fire(player, profile.currentWorld, plot)
	end)

	local function onCharacter(player: Player)
		task.defer(function()
			local plot = WorldService.currentPlot(player)
			if plot then
				teleport(player, plot)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local mine = assignments[player]
		assignments[player] = nil
		if mine then
			for _, plot in mine do
				plot.owner = nil
				plot.root:SetAttribute(ATTR.Owner, nil)
				plot.root:SetAttribute("OwnerName", nil)
			end
		end
	end)

	Net.onServerEvent("Travel", function(player, worldId)
		if Validate.oneOf(worldId, Worlds.byId) then
			WorldService.travel(player, worldId :: string)
		end
	end)
	Net.onServerEvent("UnlockWorld", function(player, worldId)
		if Validate.oneOf(worldId, Worlds.byId) then
			WorldService.unlock(player, worldId :: string)
		end
	end)
end

return WorldService
