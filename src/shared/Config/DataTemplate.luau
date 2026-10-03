--!strict
-- The save-data template. Missing keys in old saves are filled from here
-- (TableUtil.reconcile), so adding a field only needs a default below.

local Economy = require(script.Parent.Economy)
local Worlds = require(script.Parent.Worlds)
local Types = require(script.Parent.Parent.Types)

local DataTemplate = {}

-- 1: original release. 2: tycoon builds + tutorial.
DataTemplate.version = 2

-- DataStore settings (used by DataService).
DataTemplate.store = {
	name = "CosmicCafe_Profiles_v1",
	keyPrefix = "Player_",
	-- A session lock older than this is considered dead (crashed server) and is stolen.
	lockTimeoutSeconds = 30 * 60,
	-- While another live server holds the lock, retry this many times...
	loadAttempts = 6,
	-- ...waiting this long between attempts, then steal the lock.
	loadRetryDelay = 5,
	saveAttempts = 3,
	saveRetryDelay = 2,
	-- Seconds BindToClose waits for the final saves.
	shutdownTimeout = 25,
}

function DataTemplate.new(): Types.Profile
	local worlds: { [string]: Types.WorldSave } = {}
	for _, world in Worlds.list do
		local dishes: { [string]: number } = {}
		for _, dishId in world.dishes do
			dishes[dishId] = 0
		end
		worlds[world.id] = {
			unlocked = world.unlockCost <= 0,
			dishes = dishes,
		}
	end
	local firstWorld = Worlds.byId[Worlds.first]
	worlds[firstWorld.id].dishes[firstWorld.dishes[1]] = Economy.startingDishLevel
	local builds: { [string]: { [string]: string } } = {}
	for _, world in Worlds.list do
		builds[world.id] = {}
	end

	return {
		version = DataTemplate.version,
		money = Economy.startingMoney,
		runEarnings = 0,
		lifetimeEarnings = 0,
		starChefs = 0,
		totalStarChefs = 0,
		franchiseCount = 0,
		franchiseNodes = {},
		currentWorld = firstWorld.id,
		worlds = worlds,
		builds = builds,
		tutorial = {
			step = 1,
			done = false,
		},
		staff = {
			nextId = 1,
			items = {},
		},
		codex = {
			species = {},
			recipes = {},
		},
		daily = {
			streak = 0,
			lastClaimDay = 0,
			criticDay = 0,
		},
		offline = {
			lastOnline = 0,
		},
		settings = {
			autoBuy = false,
		},
		stats = {
			served = 0,
			goldenServed = 0,
			playSeconds = 0,
			bestStreak = 0,
			cashCollected = 0,
		},
	}
end

-- Version upgrades that need more than filling in new fields. Runs BEFORE
-- reconcile on raw saved data.
function DataTemplate.migrate(data: { [string]: any })
	local version = data.version or 1
	if version < 2 then
		-- Players from before the tycoon redesign already know how to play.
		local stats = data.stats
		if type(stats) == "table" and type(stats.served) == "number" and stats.served > 0 then
			data.tutorial = { step = 1, done = true }
		end
	end
end

return DataTemplate
