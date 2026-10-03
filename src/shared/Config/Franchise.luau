--!strict
-- Franchise (prestige) tree. Nodes are bought with unspent Star Chefs; the
-- +income bonus always uses *total* Star Chefs earned, so spending is free.

export type Node = {
	id: string,
	displayName: string,
	icon: string,
	description: string,
	cost: number,
	requires: { string },
	-- Effects (all optional, summed across owned nodes)
	incomeBonus: number?, -- additive to the global income multiplier
	offlineHours: number?, -- added to the offline cap
	startMoney: number?, -- money at the start of every run
	startDishLevel: number?, -- first dish of every unlocked world starts at this level
	tipBonus: number?, -- additive to every tip multiplier
	goldenChanceMultiplier: number?,
	autoBuy: boolean?,
}

local Franchise = {}

local nodes: { Node } = {
	{
		id = "SeedMoney",
		displayName = "Seed Money",
		icon = "💰",
		description = "Start every run with $5K.",
		cost = 1,
		requires = {},
		startMoney = 5000,
	},
	{
		id = "AutoBuy",
		displayName = "Auto-Buy",
		icon = "🤖",
		description = "Unlocks the Auto-Buy toggle: automatically buys the best upgrade.",
		cost = 2,
		requires = {},
		autoBuy = true,
	},
	{
		id = "LongNap1",
		displayName = "Long Nap I",
		icon = "😴",
		description = "+2h offline earnings cap.",
		cost = 2,
		requires = {},
		offlineHours = 2,
	},
	{
		id = "TipJar",
		displayName = "Tip Jar",
		icon = "🫙",
		description = "+0.25 to every customer tip multiplier.",
		cost = 3,
		requires = { "SeedMoney" },
		tipBonus = 0.25,
	},
	{
		id = "HeadStart",
		displayName = "Head Start",
		icon = "🏁",
		description = "The first dish of each unlocked world starts at level 10.",
		cost = 4,
		requires = { "SeedMoney" },
		startDishLevel = 10,
	},
	{
		id = "LongNap2",
		displayName = "Long Nap II",
		icon = "🛌",
		description = "+4h offline earnings cap.",
		cost = 5,
		requires = { "LongNap1" },
		offlineHours = 4,
	},
	{
		id = "GoldenRadar",
		displayName = "Golden Radar",
		icon = "📡",
		description = "Golden Aliens appear twice as often.",
		cost = 6,
		requires = { "TipJar" },
		goldenChanceMultiplier = 2,
	},
	{
		id = "LongNap3",
		displayName = "Long Nap III",
		icon = "🌙",
		description = "+4h offline earnings cap.",
		cost = 10,
		requires = { "LongNap2" },
		offlineHours = 4,
	},
	{
		id = "MegaFranchise",
		displayName = "Mega Franchise",
		icon = "🏙️",
		description = "+50% income, forever.",
		cost = 15,
		requires = { "HeadStart", "GoldenRadar" },
		incomeBonus = 0.5,
	},
}

Franchise.nodes = nodes
Franchise.byId = {} :: { [string]: Node }
for _, node in nodes do
	Franchise.byId[node.id] = node
end

return Franchise
