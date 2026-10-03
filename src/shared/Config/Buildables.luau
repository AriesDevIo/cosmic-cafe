--!strict
-- Tycoon buildables for GENERATED lots (plots without a hand-built
-- "Buildables" folder). Hand-built plots describe their buildables with model
-- attributes instead (see docs/MAP_CONTRACT.md); both end up as BuildDefs.
--
-- Every world gets the same lot layout. Station slots map to the world's dishes
-- in order; the first station is free, the others cost the dish's baseCost.
-- Everything else costs `cost * world.priceScale`.

local Dishes = require(script.Parent.Dishes)
local Worlds = require(script.Parent.Worlds)

export type BuildKind = "Station" | "Table" | "Counter" | "Structure" | "Decor"

-- What the game needs to know about a buildable (from config or map attributes).
export type BuildDef = {
	id: string,
	displayName: string,
	kind: string,
	dish: string?, -- Station only
	cost: number,
	order: number,
	requires: { string },
}

-- One part of a generated buildable model, in lot space (+Z = front).
export type PartSpec = {
	name: string,
	size: Vector3,
	offset: Vector3, -- center of the part
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	seat: boolean?, -- create a Seat instead of a Part
	collide: boolean?,
}

export type Template = {
	id: string,
	displayName: string?, -- stations take their name from the dish
	kind: string,
	slot: number?, -- Station: index into world.dishes
	cost: number, -- non-stations, multiplied by world.priceScale
	order: number,
	requires: { string },
	pad: Vector3, -- buy pad position in lot space
	parts: { PartSpec },
}

local Buildables = {}

-- Pads and padding ---------------------------------------------------------------

Buildables.maxVisiblePads = 3

Buildables.pad = {
	size = Vector3.new(0.6, 7, 7), -- cylinder: X is height
	color = Color3.fromRGB(80, 255, 140),
	lockedColor = Color3.fromRGB(255, 120, 90), -- shown when you can't afford it
	touchCooldown = 1.0, -- seconds between buy attempts per player
}

-- Build animation (client) and server timing.
Buildables.animation = {
	riseFrom = 10, -- studs below the final position
	stagger = 0.03, -- seconds between parts
	duration = 0.45,
	popScale = 1.08,
	bigPurchaseShakeAt = 1000, -- camera shake for builds costing at least this (x world priceScale)
}

-- Layout -------------------------------------------------------------------------

local WOOD = Color3.fromRGB(150, 100, 60)
local DARK_WOOD = Color3.fromRGB(105, 70, 45)
local WHITE = Color3.fromRGB(245, 245, 240)
local METAL = Color3.fromRGB(160, 165, 175)

local function station(slot: number, x: number, accent: Color3, requires: { string }, order: number): Template
	return {
		id = "Station" .. slot,
		kind = "Station",
		slot = slot,
		cost = 0,
		order = order,
		requires = requires,
		pad = Vector3.new(x, 0, -18),
		parts = {
			{ name = "Base", size = Vector3.new(7, 3.6, 4.5), offset = Vector3.new(x, 1.8, -26), color = WOOD },
			{ name = "Top", size = Vector3.new(7.4, 0.4, 4.9), offset = Vector3.new(x, 3.8, -26), color = WHITE },
			{
				name = "Machine",
				size = Vector3.new(3, 2.4, 2.4),
				offset = Vector3.new(x, 5.2, -26.6),
				color = accent,
				material = Enum.Material.SmoothPlastic,
			},
			{ name = "Pole", size = Vector3.new(0.4, 6, 0.4), offset = Vector3.new(x + 3, 6.8, -28), color = METAL },
			{
				name = "Canopy",
				size = Vector3.new(8, 0.5, 6),
				offset = Vector3.new(x, 9.9, -26),
				color = accent,
				material = Enum.Material.SmoothPlastic,
			},
		},
	}
end

local function tableAt(index: number, x: number, z: number, cost: number, requires: { string }, order: number): Template
	return {
		id = "Table" .. index,
		displayName = "Table " .. index,
		kind = "Table",
		cost = cost,
		order = order,
		requires = requires,
		pad = Vector3.new(x, 0, z),
		parts = {
			{
				name = "Top",
				size = Vector3.new(0.5, 6, 6),
				offset = Vector3.new(x, 3, z),
				color = WHITE,
				shape = Enum.PartType.Cylinder,
			},
			{ name = "Leg", size = Vector3.new(0.8, 2.8, 0.8), offset = Vector3.new(x, 1.4, z), color = METAL },
			{
				name = "SeatA",
				size = Vector3.new(2.2, 1, 2.2),
				offset = Vector3.new(x - 4.5, 1.6, z),
				color = Color3.fromRGB(230, 90, 90),
				seat = true,
			},
			{
				name = "SeatB",
				size = Vector3.new(2.2, 1, 2.2),
				offset = Vector3.new(x + 4.5, 1.6, z),
				color = Color3.fromRGB(230, 90, 90),
				seat = true,
			},
		},
	}
end

-- Lot space: x -40..40, z -45..45, kitchen at the back (-Z), street at the front (+Z).
local templates: { Template } = {
	station(1, -24, Color3.fromRGB(230, 70, 70), {}, 1),
	tableAt(1, -14, 4, 15, { "Station1" }, 2),
	station(2, -12, Color3.fromRGB(240, 150, 200), { "Station1" }, 3),
	{
		id = "Counter",
		displayName = "Serving Counter",
		kind = "Counter",
		cost = 40,
		order = 4,
		requires = { "Table1" },
		pad = Vector3.new(0, 0, -6),
		parts = {
			{ name = "Body", size = Vector3.new(36, 3.6, 3), offset = Vector3.new(0, 1.8, -12), color = DARK_WOOD },
			{ name = "Top", size = Vector3.new(36.6, 0.4, 3.6), offset = Vector3.new(0, 3.8, -12), color = WHITE },
		},
	},
	tableAt(2, 0, 4, 60, { "Table1" }, 5),
	station(3, 0, Color3.fromRGB(240, 170, 60), { "Station2" }, 6),
	{
		id = "Awning",
		displayName = "Striped Awning",
		kind = "Structure",
		cost = 250,
		order = 7,
		requires = { "Counter" },
		pad = Vector3.new(-20, 0, -6),
		parts = {
			{ name = "PoleL", size = Vector3.new(0.6, 9, 0.6), offset = Vector3.new(-18.5, 4.5, -10), color = METAL },
			{ name = "PoleR", size = Vector3.new(0.6, 9, 0.6), offset = Vector3.new(18.5, 4.5, -10), color = METAL },
			{
				name = "StripeA",
				size = Vector3.new(38, 0.4, 2),
				offset = Vector3.new(0, 9.2, -13),
				color = Color3.fromRGB(230, 60, 60),
			},
			{ name = "StripeB", size = Vector3.new(38, 0.4, 2), offset = Vector3.new(0, 9.0, -11), color = WHITE },
			{
				name = "StripeC",
				size = Vector3.new(38, 0.4, 2),
				offset = Vector3.new(0, 8.8, -9),
				color = Color3.fromRGB(230, 60, 60),
			},
		},
	},
	tableAt(3, 14, 4, 400, { "Table2" }, 8),
	{
		id = "Planters",
		displayName = "Flower Planters",
		kind = "Decor",
		cost = 800,
		order = 9,
		requires = { "Counter" },
		pad = Vector3.new(-30, 0, 36),
		parts = {
			{ name = "BoxL", size = Vector3.new(5, 2, 5), offset = Vector3.new(-34, 1, 38), color = DARK_WOOD },
			{
				name = "FlowersL",
				size = Vector3.new(4.4, 1.4, 4.4),
				offset = Vector3.new(-34, 2.6, 38),
				color = Color3.fromRGB(110, 200, 90),
				material = Enum.Material.Grass,
			},
			{ name = "BoxR", size = Vector3.new(5, 2, 5), offset = Vector3.new(34, 1, 38), color = DARK_WOOD },
			{
				name = "FlowersR",
				size = Vector3.new(4.4, 1.4, 4.4),
				offset = Vector3.new(34, 2.6, 38),
				color = Color3.fromRGB(110, 200, 90),
				material = Enum.Material.Grass,
			},
		},
	},
	station(4, 12, Color3.fromRGB(250, 220, 120), { "Station3" }, 10),
	{
		id = "BackWall",
		displayName = "Kitchen Wall",
		kind = "Structure",
		cost = 5000,
		order = 11,
		requires = { "Awning" },
		pad = Vector3.new(30, 0, -20),
		parts = {
			{
				name = "Wall",
				size = Vector3.new(80, 12, 1.5),
				offset = Vector3.new(0, 6, -33),
				color = Color3.fromRGB(250, 235, 210),
			},
			{ name = "Trim", size = Vector3.new(80, 1, 2), offset = Vector3.new(0, 12.4, -33), color = DARK_WOOD },
		},
	},
	tableAt(4, -14, 20, 3000, { "Table3" }, 12),
	{
		id = "StringLights",
		displayName = "String Lights",
		kind = "Decor",
		cost = 12000,
		order = 13,
		requires = { "BackWall" },
		pad = Vector3.new(-30, 0, 12),
		parts = {
			{
				name = "WireA",
				size = Vector3.new(0.3, 0.3, 40),
				offset = Vector3.new(-22, 11, 8),
				color = Color3.fromRGB(255, 230, 140),
				material = Enum.Material.Neon,
			},
			{
				name = "WireB",
				size = Vector3.new(0.3, 0.3, 40),
				offset = Vector3.new(22, 11, 8),
				color = Color3.fromRGB(255, 230, 140),
				material = Enum.Material.Neon,
			},
			{ name = "PostA", size = Vector3.new(0.5, 11, 0.5), offset = Vector3.new(-22, 5.5, 28), color = METAL },
			{ name = "PostB", size = Vector3.new(0.5, 11, 0.5), offset = Vector3.new(22, 5.5, 28), color = METAL },
		},
	},
	station(5, 24, Color3.fromRGB(200, 120, 70), { "Station4" }, 14),
	tableAt(5, 0, 20, 25000, { "Table4" }, 15),
	{
		id = "NeonSign",
		displayName = "Neon Sign",
		kind = "Decor",
		cost = 80000,
		order = 16,
		requires = { "StringLights" },
		pad = Vector3.new(30, 0, -6),
		parts = {
			{
				name = "Board",
				size = Vector3.new(20, 5, 0.6),
				offset = Vector3.new(0, 15.5, -32.5),
				color = Color3.fromRGB(40, 30, 60),
			},
			{
				name = "Glow",
				size = Vector3.new(18, 3, 0.3),
				offset = Vector3.new(0, 15.5, -32.1),
				color = Color3.fromRGB(255, 80, 200),
				material = Enum.Material.Neon,
			},
		},
	},
	tableAt(6, 14, 20, 150000, { "Table5" }, 17),
	{
		id = "Fountain",
		displayName = "Fountain",
		kind = "Decor",
		cost = 500000,
		order = 18,
		requires = { "NeonSign" },
		pad = Vector3.new(30, 0, 30),
		parts = {
			{
				name = "Basin",
				size = Vector3.new(2, 9, 9),
				offset = Vector3.new(30, 1, 34),
				color = METAL,
				shape = Enum.PartType.Cylinder,
			},
			{
				name = "Water",
				size = Vector3.new(0.4, 8, 8),
				offset = Vector3.new(30, 2, 34),
				color = Color3.fromRGB(90, 170, 255),
				material = Enum.Material.Glass,
				shape = Enum.PartType.Cylinder,
				transparency = 0.3,
			},
			{ name = "Spout", size = Vector3.new(1, 4, 1), offset = Vector3.new(30, 3.5, 34), color = METAL },
		},
	},
}

Buildables.templates = templates

-- Cylinders lie along X; rotate them upright.
Buildables.uprightCylinder = CFrame.Angles(0, 0, math.rad(90))

local function stationName(dishId: string): string
	local dish = Dishes.byId[dishId]
	return dish.stationName or (dish.displayName .. " Station")
end

-- BuildDefs + templates for a world's generated lot (stations beyond the
-- world's dish count are skipped, as is anything requiring them).
function Buildables.forWorld(worldId: string): ({ BuildDef }, { [string]: Template })
	local world = Worlds.byId[worldId]
	local defs: { BuildDef } = {}
	local byId: { [string]: Template } = {}
	local skipped: { [string]: boolean } = {}
	for _, template in templates do
		local dishId = if template.slot then world.dishes[template.slot] else nil
		local missing = template.kind == "Station" and dishId == nil
		for _, required in template.requires do
			if skipped[required] then
				missing = true
			end
		end
		if missing then
			skipped[template.id] = true
			continue
		end
		local cost
		if template.kind == "Station" then
			local dish = Dishes.byId[dishId :: string]
			cost = if template.slot == 1 then 0 else dish.baseCost
		else
			cost = template.cost * world.priceScale
		end
		table.insert(defs, {
			id = template.id,
			displayName = if dishId then stationName(dishId) else template.displayName or template.id,
			kind = template.kind,
			dish = dishId,
			cost = cost,
			order = template.order,
			requires = template.requires,
		})
		byId[template.id] = template
	end
	return defs, byId
end

-- Parses a comma-separated Requires attribute.
function Buildables.parseRequires(value: unknown): { string }
	local list = {}
	if type(value) == "string" then
		for id in string.gmatch(value, "[^,%s]+") do
			table.insert(list, id)
		end
	end
	return list
end

return Buildables
