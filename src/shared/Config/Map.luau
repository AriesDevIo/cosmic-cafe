--!strict
-- Map contract (see docs/MAP_CONTRACT.md) and placeholder layout.
-- The code never looks up map objects by path, only by CollectionService tag
-- + attributes. Anything missing is generated from the numbers below.

local Map = {}

Map.tags = {
	CafePlot = "CafePlot", -- Attribute World = "<WorldId>"
	Station = "Station", -- Attribute Dish = "<DishId>"
	Table = "Table",
	CustomerSpawn = "CustomerSpawn",
	Counter = "Counter",
	WorldPortal = "WorldPortal", -- Attribute Target = "<WorldId>"
	UnlockGate = "UnlockGate", -- Attribute World = "<WorldId>"
	-- Runtime tags set by the server (not placed by map builders)
	Customer = "CafeCustomer",
	BuyPad = "BuyPad",
	ActiveStation = "CafeStation", -- state part of every station in use (tagged or built)
	CashStack = "CashStack",
}

-- Folder inside a CafePlot model that holds its tycoon buildables.
Map.buildablesFolder = "Buildables"
Map.padSpotName = "PadSpot"

Map.attributes = {
	World = "World",
	Dish = "Dish",
	Target = "Target",
	PlotId = "PlotId", -- optional: link loose parts to a plot with the same PlotId
	Owner = "OwnerUserId", -- runtime
}

-- Stations/tables/counters/spawns that are not inside a CafePlot model and have
-- no PlotId belong to the nearest plot within this many studs.
Map.plotRadius = 150

Map.prompt = {
	maxDistance = 12,
	holdDuration = 0,
	unlockHoldDuration = 0.5, -- UnlockGate prompts need a short hold
}

Map.labelMaxDistance = 80 -- placeholder name labels

Map.portalCooldown = 2 -- seconds between portal touches per player

-- Placeholder layout. Offsets are in plot space (plot CFrame), +Z = front.
Map.placeholder = {
	worldOrigin = Vector3.new(0, 0, 0), -- world 1's first generated plot
	worldSpacing = Vector3.new(1200, 0, 0), -- next world's area
	plotSpacing = Vector3.new(0, 0, 110), -- next plot inside a world
	extraPlotSpacing = Vector3.new(110, 0, 0), -- extra plots next to a hand-built row
	plotSize = Vector3.new(80, 1, 90),
	stationSize = Vector3.new(7, 4, 5),
	stationRowZ = -32,
	stationSpacing = 11,
	counterOffset = Vector3.new(0, 2.5, -14),
	counterSize = Vector3.new(44, 4, 3),
	tableOffsets = {
		Vector3.new(-24, 1.5, 6),
		Vector3.new(-8, 1.5, 6),
		Vector3.new(8, 1.5, 6),
		Vector3.new(24, 1.5, 6),
		Vector3.new(-16, 1.5, 22),
		Vector3.new(16, 1.5, 22),
	},
	tableSize = Vector3.new(5, 3, 5),
	customerSpawnOffset = Vector3.new(0, 1, 52),
	playerSpawnOffset = Vector3.new(0, 4, -22),
	portalOffsetX = 50, -- generated portals line up on the plot's right side
	portalSpacingZ = 14,
	portalSize = Vector3.new(8, 10, 1),
}

Map.customer = {
	rootSize = Vector3.new(2, 2, 2),
	bodySize = Vector3.new(2.6, 3, 2.6),
	headSize = Vector3.new(2.4, 2.4, 2.4),
	eyeSize = Vector3.new(0.45, 0.45, 0.45),
	antennaSize = Vector3.new(0.25, 1.2, 0.25),
	standOffset = Vector3.new(0, 0, 4), -- where a customer stands relative to their table
	goldenSparkleRate = 20,
}

return Map
