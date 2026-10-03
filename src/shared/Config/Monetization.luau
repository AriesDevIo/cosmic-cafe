--!strict
-- Monetization hooks. IDs are 0 until real game passes exist; with id 0 the
-- server treats the pass as not owned (unless `studioGrantsAll` is on in Studio).
-- Worlds are never sold: every pass is a convenience or cosmetic.

export type Pass = {
	id: string,
	gamePassId: number,
	displayName: string,
	description: string,
	priceRobux: number, -- display only
}

local Monetization = {}

Monetization.studioGrantsAll = false

Monetization.passes = {
	DoubleMoney = {
		id = "DoubleMoney",
		gamePassId = 0,
		displayName = "2x Money",
		description = "Double every coin you earn, forever.",
		priceRobux = 0,
	},
	AutoServe = {
		id = "AutoServe",
		gamePassId = 0,
		displayName = "Auto-Serve",
		description = "Customers are served automatically in every world, even without a Waiter.",
		priceRobux = 0,
	},
	OfflinePlus = {
		id = "OfflinePlus",
		gamePassId = 0,
		displayName = "+Offline Time",
		description = "+4h offline earnings cap.",
		priceRobux = 0,
	},
	VIPDecor = {
		id = "VIPDecor",
		gamePassId = 0,
		displayName = "VIP Decor",
		description = "Golden trim and neon signs for your cafe. Purely cosmetic.",
		priceRobux = 0,
	},
} :: { [string]: Pass }

Monetization.doubleMoneyMultiplier = 2

-- Max seconds a joining player waits for pass ownership before offline pay.
Monetization.ownershipTimeout = 10

-- Badge ids (0 = disabled).
Monetization.badges = {
	FirstDiscovery = 0, -- first player on a server to discover a recipe
	GoldenAlien = 0,
	FirstFranchise = 0,
}

return Monetization
