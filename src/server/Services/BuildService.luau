--!strict
-- Tycoon build loop.
--
-- A CafePlot with a "Buildables" folder starts as an empty lot: every buildable
-- model is moved to ServerStorage (keeping its CFrame). The owner sees up to
-- Buildables.maxVisiblePads glowing buy pads (cheapest affordable-order first)
-- for buildables whose Requires are owned; stepping on a pad buys it, the model
-- moves back into the plot and the client animates it rising in. Owned build
-- ids are saved, so on join everything is restored instantly.
--
-- Built stations/tables/counters are registered on the Plot so CafeService
-- only uses what the player bought. Plots without a Buildables folder keep the
-- old behaviour (everything present, dishes unlocked from the Menu).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Buildables = require(Shared.Config.Buildables)
local Dishes = require(Shared.Config.Dishes)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Signal = require(Shared.Util.Signal)
local Worlds = require(Shared.Config.Worlds)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

type Plot = WorldService.Plot
type BuildDef = Buildables.BuildDef

export type BuildInfo = {
	def: BuildDef,
	model: Model,
	home: Instance, -- where the model lives when built
	padCFrame: CFrame,
	built: boolean,
}

type PlotBuilds = {
	plot: Plot,
	storage: Folder,
	defs: { BuildDef },
	infos: { [string]: BuildInfo },
	pads: { [string]: BasePart },
}

local BuildService = {}

-- (player, plot, info, animated) after a buildable appears in a plot.
BuildService.built = Signal.new() :: Signal.Signal<Player, Plot, BuildInfo, boolean>

local KINDS = { Station = true, Table = true, Counter = true, Structure = true, Decor = true }
local PAD = Buildables.pad

local byPlot: { [Plot]: PlotBuilds } = {}
local storageRoot: Folder
local padFolder: Folder
local lastTouch: { [number]: number } = {} -- UserId -> os.clock()

-- Indexing -------------------------------------------------------------------------

local function statePart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child.Name ~= Map.padSpotName then
			return child
		end
	end
	return nil
end

local function readDef(model: Model, plot: Plot): BuildDef?
	local id = model:GetAttribute("BuildId")
	local cost = model:GetAttribute("Cost")
	local kind = model:GetAttribute("Kind")
	local dish = model:GetAttribute("Dish")
	local function bad(reason: string): nil
		warn(string.format("[BuildService] %s skipped: %s", model:GetFullName(), reason))
		return nil
	end
	if type(id) ~= "string" or id == "" then
		return bad("missing BuildId")
	end
	if type(cost) ~= "number" or cost < 0 then
		return bad("Cost must be a number >= 0")
	end
	if type(kind) ~= "string" or not KINDS[kind] then
		return bad("Kind must be Station, Table, Counter, Structure or Decor")
	end
	if kind == "Station" then
		local dishDef = if type(dish) == "string" then Dishes.byId[dish] else nil
		if dishDef == nil or dishDef.world ~= plot.worldId then
			return bad("Station needs a Dish of world " .. plot.worldId)
		end
	end
	local order = model:GetAttribute("Order")
	local name = model:GetAttribute("DisplayName")
	if type(name) ~= "string" then
		name = if kind == "Station" then Dishes.byId[dish :: string].stationName or model.Name else model.Name
	end
	return {
		id = id,
		displayName = name :: string,
		kind = kind,
		dish = if kind == "Station" then dish :: string else nil,
		cost = cost,
		order = if type(order) == "number" then order else math.huge,
		requires = Buildables.parseRequires(model:GetAttribute("Requires")),
	}
end

local function index(plot: Plot)
	if not plot.buildMode or byPlot[plot] then
		return
	end
	local folder = plot.root:FindFirstChild(Map.buildablesFolder)
	if folder == nil then
		return
	end
	local storage = Instance.new("Folder")
	storage.Name = plot.id
	storage.Parent = storageRoot
	local entry: PlotBuilds = { plot = plot, storage = storage, defs = {}, infos = {}, pads = {} }
	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local def = readDef(child, plot)
		if def == nil then
			continue
		end
		if entry.infos[def.id] then
			warn("[BuildService] duplicate BuildId " .. def.id .. " in " .. plot.root:GetFullName())
			continue
		end
		local padSpot = child:FindFirstChild(Map.padSpotName, true)
		local padCFrame: CFrame
		if padSpot and padSpot:IsA("BasePart") then
			padCFrame = padSpot.CFrame
			padSpot.Transparency = 1
			padSpot.CanCollide = false
		else
			padCFrame = child:GetPivot()
			warn("[BuildService] " .. child:GetFullName() .. " has no PadSpot part, using its pivot")
		end
		table.insert(entry.defs, def)
		entry.infos[def.id] = { def = def, model = child, home = folder, padCFrame = padCFrame, built = false }
		child.Parent = storage
	end
	byPlot[plot] = entry
end

-- Plot registration ----------------------------------------------------------------------

local function register(plot: Plot, info: BuildInfo)
	local model = info.model
	local kind = info.def.kind
	local part = statePart(model)
	if part == nil then
		return
	end
	if kind == "Station" and info.def.dish then
		plot.stations[info.def.dish] = part
	elseif kind == "Counter" then
		table.insert(plot.counters, part)
	elseif kind == "Table" then
		table.insert(plot.tables, part)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Seat") then
				table.insert(plot.seats, descendant)
			end
		end
	end
end

local function unregister(plot: Plot, info: BuildInfo)
	local model = info.model
	for dishId, part in plot.stations do
		if part:IsDescendantOf(model) then
			plot.stations[dishId] = nil
		end
	end
	local function strip(list: { any })
		for i = #list, 1, -1 do
			if list[i]:IsDescendantOf(model) then
				table.remove(list, i)
			end
		end
	end
	strip(plot.counters)
	strip(plot.tables)
	strip(plot.seats)
end

local function place(player: Player, entry: PlotBuilds, info: BuildInfo, animate: boolean)
	if info.built then
		return
	end
	info.built = true
	info.model:SetAttribute("BuiltAt", if animate then workspace:GetServerTimeNow() else 0)
	info.model:SetAttribute(Map.attributes.Owner, player.UserId)
	info.model.Parent = info.home
	register(entry.plot, info)
	BuildService.built:fire(player, entry.plot, info, animate)
end

local function unplace(entry: PlotBuilds, info: BuildInfo)
	if not info.built then
		return
	end
	info.built = false
	unregister(entry.plot, info)
	info.model.Parent = entry.storage
end

-- Pads ----------------------------------------------------------------------------------

local function clearPads(entry: PlotBuilds)
	for id, pad in entry.pads do
		pad:Destroy()
		entry.pads[id] = nil
	end
end

local buy: (player: Player, entry: PlotBuilds, buildId: string) -> ()

local function makePad(entry: PlotBuilds, info: BuildInfo, owner: Player): BasePart
	local pad = Instance.new("Part")
	pad.Name = "BuyPad_" .. info.def.id
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = PAD.size
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = PAD.color
	pad.Transparency = 0.15
	local position = info.padCFrame.Position + Vector3.new(0, PAD.size.X / 2, 0)
	pad.CFrame = CFrame.new(position) * Buildables.uprightCylinder
	pad:SetAttribute("BuildId", info.def.id)
	pad:SetAttribute("DisplayName", info.def.displayName)
	pad:SetAttribute("Cost", info.def.cost)
	pad:SetAttribute("Kind", info.def.kind)
	pad:SetAttribute("Dish", info.def.dish)
	pad:SetAttribute(Map.attributes.Owner, owner.UserId)
	pad.Parent = padFolder
	CollectionService:AddTag(pad, Map.tags.BuyPad)
	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if player and player == entry.plot.owner then
			buy(player, entry, info.def.id)
		end
	end)
	return pad
end

-- Shows pads for what the owner can buy next (cheapest first).
local function refreshPads(entry: PlotBuilds)
	local owner = entry.plot.owner
	local profile = if owner then DataService.get(owner) else nil
	if owner == nil or profile == nil then
		clearPads(entry)
		return
	end
	local wanted: { [string]: boolean } = {}
	for _, def in Progression.availableBuilds(profile, entry.plot.worldId, entry.defs, Buildables.maxVisiblePads) do
		wanted[def.id] = true
		local existing: BasePart? = entry.pads[def.id]
		if existing == nil then
			entry.pads[def.id] = makePad(entry, entry.infos[def.id], owner)
		end
	end
	for id, pad in entry.pads do
		if not wanted[id] then
			pad:Destroy()
			entry.pads[id] = nil
		end
	end
end

-- Buying ------------------------------------------------------------------------------

buy = function(player: Player, entry: PlotBuilds, buildId: string)
	local now = os.clock()
	if (lastTouch[player.UserId] or 0) + PAD.touchCooldown > now then
		return
	end
	lastTouch[player.UserId] = now
	local profile = DataService.get(player)
	local info = entry.infos[buildId]
	if profile == nil or info == nil or info.built then
		return
	end
	local ok, err = Progression.buyBuild(profile, entry.plot.worldId, info.def)
	if not ok then
		if err == "Not enough money" then
			Net.fire(
				player,
				"Notify",
				"Need " .. BigNum.money(info.def.cost) .. " for " .. info.def.displayName,
				"error"
			)
		end
		return
	end
	place(player, entry, info, true)
	refreshPads(entry)
	StateService.markDirty(player)
	StateService.pushRuntime(player)
	Net.fire(player, "Effect", "Build", {
		id = buildId,
		name = info.def.displayName,
		cost = info.def.cost,
		position = info.padCFrame.Position,
		big = info.def.cost >= Buildables.animation.bigPurchaseShakeAt * Worlds.byId[entry.plot.worldId].priceScale,
	})
end

-- Sync ----------------------------------------------------------------------------------

-- Makes the plot match the owner's save (instant, no animation).
local function sync(player: Player, plot: Plot)
	local entry = byPlot[plot]
	local profile = DataService.get(player)
	if profile == nil then
		return
	end
	if entry == nil then
		-- No buildables: the old "everything is there" plot. The first dish is free.
		local world = Worlds.byId[plot.worldId]
		local save = profile.worlds[plot.worldId]
		if save.unlocked and (save.dishes[world.dishes[1]] or 0) == 0 then
			save.dishes[world.dishes[1]] = 1
			StateService.markDirty(player)
		end
		return
	end
	if Progression.reconcileBuilds(profile, plot.worldId, entry.defs) then
		StateService.markDirty(player)
	end
	for id, info in entry.infos do
		local owned = Progression.ownsBuild(profile, plot.worldId, id)
		if owned and not info.built then
			place(player, entry, info, false)
		elseif not owned and info.built then
			unplace(entry, info)
		end
	end
	refreshPads(entry)
	StateService.pushRuntime(player)
end

-- Re-syncs every plot of a player (after a Franchise reset, world unlock...).
function BuildService.resync(player: Player)
	for _, plot in WorldService.plotsOf(player) do
		sync(player, plot)
	end
end

-- Does the player's plot in `worldId` use buildables?
function BuildService.usesBuildables(player: Player, worldId: string): boolean
	local plot = WorldService.plotsOf(player)[worldId]
	return plot ~= nil and byPlot[plot] ~= nil
end

export type LotRuntime = {
	buildMode: boolean,
	-- visible pads in the current world, cheapest first (HUD goal bar, tutorial)
	next: { { id: string, name: string, cost: number, kind: string, dish: string? } },
	-- built buildable ids by kind in the current world
	built: { [string]: number },
}

function BuildService.lotRuntime(player: Player): LotRuntime
	local plot = WorldService.currentPlot(player)
	local entry = if plot then byPlot[plot] else nil
	local profile = DataService.get(player)
	local result: LotRuntime = { buildMode = entry ~= nil, next = {}, built = {} }
	if entry and profile then
		for _, def in Progression.availableBuilds(profile, entry.plot.worldId, entry.defs, Buildables.maxVisiblePads) do
			table.insert(result.next, {
				id = def.id,
				name = def.displayName,
				cost = def.cost,
				kind = def.kind,
				dish = def.dish,
			})
		end
		for _, info in entry.infos do
			if info.built then
				result.built[info.def.kind] = (result.built[info.def.kind] or 0) + 1
			end
		end
	end
	return result
end

function BuildService.init()
	storageRoot = Instance.new("Folder")
	storageRoot.Name = "CosmicCafeBuildables"
	storageRoot.Parent = ServerStorage
	for _, plot in WorldService.allPlots() do
		index(plot)
	end
	WorldService.plotCreated:connect(index)
	padFolder = Instance.new("Folder")
	padFolder.Name = "CosmicCafePads"
	padFolder.Parent = workspace
	StateService.addRuntimeProvider("lot", BuildService.lotRuntime)
end

function BuildService.start()
	WorldService.plotAssigned:connect(function(player, plot)
		sync(player, plot)
	end)
	WorldService.plotReleased:connect(function(_player, plot)
		local entry = byPlot[plot]
		if entry then
			clearPads(entry)
			for _, info in entry.infos do
				unplace(entry, info)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player.UserId] = nil
	end)
end

return BuildService
