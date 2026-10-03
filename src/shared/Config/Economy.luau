--!strict
-- Global economy tuning. Every pacing knob lives here (or in the per-world /
-- per-dish config) so the services never contain magic numbers.
-- Run `lune run scripts/simulate` after changing anything in this file.

local Economy = {}

Economy.startingMoney = 0
-- Level the first dish of the first world starts at, so the first sale is instant.
Economy.startingDishLevel = 1

-- Cost of dish level n (n = levels already owned): baseCost * costGrowth^n.
-- costGrowth is set per world in Worlds.luau (1.07 early, 1.12-1.15 from world 3).
Economy.defaultCostGrowth = 1.07

-- Income per serving grows linearly with level (baseIncome * level). A per-level
-- *multiplicative* income growth >= costGrowth would make every upgrade cheaper
-- than the last (runaway), so it is kept at 1.0 and the "income growth" of the
-- design doc is expressed through the per-dish base ratios + milestones instead.
Economy.incomeLevelGrowth = 1.0

-- Manual play: serving a customer yourself within `window` seconds of the last
-- serve grows the tip streak. Waiter serves never build a streak.
Economy.streak = {
	window = 8,
	perServe = 0.05,
	maxMultiplier = 2.5,
}

-- Kitchen / service loop.
Economy.cafe = {
	tickInterval = 0.1, -- server simulation step (seconds)
	trayCapacity = 12, -- ready portions a station can hold before it stops cooking
	waiterServeInterval = 1.2, -- seconds between Waiter serves at rarity multiplier 1
	autoServePassInterval = 2.0, -- game pass auto-serve speed when no Waiter is hired
	customerPatience = 45, -- seconds a customer waits before leaving
	customerWalkSpeed = 12, -- studs/second for the walk tween
	-- Customers are this many times likelier to order a dish that is already cooked.
	readyOrderBias = 3,
	-- Fraction of a world's theoretical rate that keeps running while you are
	-- in a different world and that world has a Manager (before rarity bonus).
	managerBaseEfficiency = 0.5,
	managerMaxEfficiency = 1.0,
}

Economy.offline = {
	baseCapHours = 2,
	maxCapHours = 12,
	gamePassBonusHours = 4,
	efficiency = 0.5, -- fraction of automated income earned while offline
	directorEfficiencyPerRarity = 0.1, -- extra efficiency per Director rarity multiplier step
	minSecondsAway = 60, -- shorter absences pay nothing (and show no popup)
}

Economy.prestige = {
	-- totalStarChefs = floor((lifetimeEarnings / divisor) ^ exponent)
	divisor = 6e7,
	exponent = 0.5,
	incomeBonusPerStarChef = 0.06, -- +6% income per Star Chef ever earned
	minGain = 1, -- the Franchise button unlocks once a reset would give this many
}

Economy.autoBuy = {
	interval = 1.0, -- seconds between Auto-Buy purchases
}

Economy.daily = {
	-- Reward = incomePerSecond * seconds, never below `minReward`.
	baseRewardSeconds = 120,
	perStreakDaySeconds = 60,
	maxStreakDays = 7, -- streak bonus stops growing after this many days
	streakGraceHours = 48, -- miss more than this and the streak resets
	minReward = 50,
	criticRewardSeconds = 600, -- serving the Food Critic pays 10 minutes of income
	criticSpawnDelay = 90, -- seconds after joining before the critic shows up
	criticPatience = 120, -- the critic waits longer than normal customers
}

Economy.recipeLab = {
	-- Combining ingredients costs this many seconds of income (min `minCost`).
	attemptCostSeconds = 10,
	minCost = 25,
}

Economy.golden = {
	chance = 1 / 500,
	tipMultiplier = 50,
}

-- Background world income / Auto-Buy / offline timestamp refresh.
Economy.economyTickInterval = 1.0
Economy.stateSyncInterval = 0.2 -- max client state pushes per second = 1 / this
Economy.autosaveInterval = 60

-- Assumptions used ONLY by the pacing simulator (scripts/simulate.luau).
Economy.sim = {
	dt = 1, -- seconds per simulation step
	firstServeSeconds = 8, -- walk to the stall + tap the station + tap the customer
	-- How much of the theoretical rate a human gets while cooking/serving by hand.
	manualEfficiency = 0.55,
	-- With a Barista but no Waiter the player only has to serve.
	baristaOnlyEfficiency = 0.8,
	averageStreakMultiplier = 1.4, -- typical streak while actively serving
	-- Share of time a player with a Waiter still serves by hand (keeps a streak).
	activeShare = 0.5,
	-- The bot only buys upgrades that pay for themselves within this many seconds;
	-- otherwise it saves for the next world.
	maxPaybackSeconds = 600,
	-- The bot franchises once a reset would give at least this many Star Chefs
	-- AND at least franchiseGainRatio * the Star Chefs it already has.
	franchiseWhenGainAtLeast = 15,
	franchiseGainRatio = 1.0,
	-- Tree nodes the bot buys after a franchise, in priority order.
	franchiseNodeOrder = { "SeedMoney", "AutoBuy", "TipJar", "HeadStart", "LongNap1", "GoldenRadar" },
	runSeconds = 3 * 60 * 60,
	snapshotEvery = 600,
}

return Economy
