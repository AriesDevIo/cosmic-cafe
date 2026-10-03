--!strict
-- Derived numbers computed from a save + config. Pure (no Roblox services), so
-- the server, the client UI and the Lune pacing simulator all agree.

local Config = script.Parent.Parent.Config
local Customers = require(Config.Customers)
local Dishes = require(Config.Dishes)
local Economy = require(Config.Economy)
local Franchise = require(Config.Franchise)
local Monetization = require(Config.Monetization)
local Staff = require(Config.Staff)
local Worlds = require(Config.Worlds)
local Formula = require(script.Parent.Formula)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type Context = Types.Context

local Stats = {}

Stats.defaultContext = table.freeze({
	doubleMoney = false,
	autoServePass = false,
	offlinePass = false,
	weather = nil,
}) :: Context

export type FranchiseEffects = {
	incomeBonus: number,
	offlineHours: number,
	startMoney: number,
	startDishLevel: number,
	tipBonus: number,
	goldenChanceMultiplier: number,
	autoBuy: boolean,
}

function Stats.franchiseEffects(profile: Profile): FranchiseEffects
	local effects: FranchiseEffects = {
		incomeBonus = 0,
		offlineHours = 0,
		startMoney = 0,
		startDishLevel = 0,
		tipBonus = 0,
		goldenChanceMultiplier = 1,
		autoBuy = false,
	}
	for nodeId, owned in profile.franchiseNodes do
		local node = Franchise.byId[nodeId]
		if owned and node then
			effects.incomeBonus += node.incomeBonus or 0
			effects.offlineHours += node.offlineHours or 0
			effects.startMoney = math.max(effects.startMoney, node.startMoney or 0)
			effects.startDishLevel = math.max(effects.startDishLevel, node.startDishLevel or 0)
			effects.tipBonus += node.tipBonus or 0
			effects.goldenChanceMultiplier *= node.goldenChanceMultiplier or 1
			effects.autoBuy = effects.autoBuy or node.autoBuy == true
		end
	end
	return effects
end

-- Recipe bonuses: additive global income, and per-dish value multipliers.
function Stats.recipeBonuses(profile: Profile): (number, { [string]: number })
	local global = 0
	local perDish: { [string]: number } = {}
	for recipeId, discovered in profile.codex.recipes do
		local recipe = Dishes.recipeById[recipeId]
		if discovered and recipe then
			global += recipe.bonus.globalIncome or 0
			local dishId = recipe.bonus.dish
			if dishId then
				perDish[dishId] = (perDish[dishId] or 1) * (recipe.bonus.valueMultiplier or 1)
			end
		end
	end
	return global, perDish
end

-- Global income multiplier applied to every serving.
function Stats.incomeMultiplier(profile: Profile, ctx: Context): number
	local recipeGlobal = Stats.recipeBonuses(profile)
	local additive = Formula.starChefMultiplier(profile.totalStarChefs, Economy.prestige.incomeBonusPerStarChef)
		+ Stats.franchiseEffects(profile).incomeBonus
		+ recipeGlobal
	local passMultiplier = if ctx.doubleMoney then Monetization.doubleMoneyMultiplier else 1
	return additive * passMultiplier
end

-- Staff ------------------------------------------------------------------------

function Stats.slotKey(worldId: string, roleId: string): string
	local role = Staff.roles[roleId]
	if role and role.global then
		return "Global"
	end
	return worldId
end

-- The staff member working `roleId` in `worldId` (or the global slot).
function Stats.assignedStaff(profile: Profile, worldId: string, roleId: string): Types.StaffItem?
	local slot = Stats.slotKey(worldId, roleId)
	for _, item in profile.staff.items do
		if item.role == roleId and item.assigned == slot then
			return item
		end
	end
	return nil
end

function Stats.rarityMultiplier(rarity: string): number
	local def = Staff.rarities[rarity]
	return if def then def.multiplier else 1
end

-- Cook speed multiplier from the world's Barista (1 when cooking by hand).
function Stats.cookSpeed(profile: Profile, worldId: string): number
	local barista = Stats.assignedStaff(profile, worldId, "Barista")
	return if barista then Stats.rarityMultiplier(barista.rarity) else 1
end

function Stats.hasAutoCook(profile: Profile, worldId: string): boolean
	return Stats.assignedStaff(profile, worldId, "Barista") ~= nil
end

function Stats.hasAutoServe(profile: Profile, worldId: string, ctx: Context): boolean
	return ctx.autoServePass or Stats.assignedStaff(profile, worldId, "Waiter") ~= nil
end

function Stats.isAutomated(profile: Profile, worldId: string, ctx: Context): boolean
	return Stats.hasAutoCook(profile, worldId) and Stats.hasAutoServe(profile, worldId, ctx)
end

-- Seconds between automatic serves (nil when the world has no auto-serve).
function Stats.serveInterval(profile: Profile, worldId: string, ctx: Context): number?
	local waiter = Stats.assignedStaff(profile, worldId, "Waiter")
	if waiter then
		return Economy.cafe.waiterServeInterval / Stats.rarityMultiplier(waiter.rarity)
	elseif ctx.autoServePass then
		return Economy.cafe.autoServePassInterval
	end
	return nil
end

-- Fraction of a world's rate earned while the player is in another world.
function Stats.backgroundEfficiency(profile: Profile, worldId: string): number
	local manager = Stats.assignedStaff(profile, worldId, "Manager")
	if manager == nil then
		return 0
	end
	return math.min(
		Economy.cafe.managerMaxEfficiency,
		Economy.cafe.managerBaseEfficiency * Stats.rarityMultiplier(manager.rarity)
	)
end

function Stats.highestWorld(profile: Profile): Worlds.World
	local best = Worlds.byId[Worlds.first]
	for _, world in Worlds.list do
		local save = profile.worlds[world.id]
		if save and save.unlocked and world.index > best.index then
			best = world
		end
	end
	return best
end

function Stats.hireCost(worldId: string, roleId: string): number
	local role = Staff.roles[roleId]
	local world = Worlds.byId[worldId]
	return role.hireCost * world.priceScale
end

function Stats.crateCost(profile: Profile, crateId: string): number
	return Staff.crates[crateId].cost * Stats.highestWorld(profile).priceScale
end

-- Dishes -----------------------------------------------------------------------

function Stats.dishLevel(profile: Profile, dishId: string): number
	local dish = Dishes.byId[dishId]
	local save = profile.worlds[dish.world]
	return if save then save.dishes[dishId] or 0 else 0
end

-- Weather multiplier for a dish under `weather` (1 when not affected).
function Stats.weatherMultiplier(dishId: string, weatherId: string?): number
	if weatherId == nil then
		return 1
	end
	local dish = Dishes.byId[dishId]
	local world = Worlds.byId[dish.world]
	if world.weather == nil then
		return 1
	end
	for _, weather in world.weather.weathers do
		if weather.id == weatherId and table.find(dish.tags, weather.tag) then
			return weather.valueMultiplier
		end
	end
	return 1
end

-- Long-run average weather multiplier (used for background/offline rates).
function Stats.expectedWeatherMultiplier(dishId: string): number
	local dish = Dishes.byId[dishId]
	local world = Worlds.byId[dish.world]
	local config = world.weather
	if config == nil then
		return 1
	end
	local rushShare = config.rushSeconds / (config.rushSeconds + config.calmSeconds)
	local expected = 1
	for _, weather in config.weathers do
		if table.find(dish.tags, weather.tag) then
			expected += (weather.valueMultiplier - 1) * rushShare / #config.weathers
		end
	end
	return expected
end

-- Value of one serving before tips.
function Stats.dishValue(profile: Profile, ctx: Context, dishId: string): number
	local dish = Dishes.byId[dishId]
	local level = Stats.dishLevel(profile, dishId)
	local _, perDish = Stats.recipeBonuses(profile)
	return Formula.dishValue(dish.baseIncome, level, Economy.incomeLevelGrowth)
		* (perDish[dishId] or 1)
		* Stats.incomeMultiplier(profile, ctx)
		* Stats.weatherMultiplier(dishId, ctx.weather)
end

function Stats.cookTime(profile: Profile, dishId: string): number
	local dish = Dishes.byId[dishId]
	return Formula.cookTime(
		dish.cookTime,
		Stats.dishLevel(profile, dishId),
		Dishes.milestones,
		Stats.cookSpeed(profile, dish.world)
	)
end

function Stats.upgradeCost(profile: Profile, dishId: string, amount: number): number
	local dish = Dishes.byId[dishId]
	local world = Worlds.byId[dish.world]
	return Formula.cost(dish.baseCost, world.costGrowth, Stats.dishLevel(profile, dishId), amount)
end

function Stats.maxAffordable(profile: Profile, dishId: string): number
	local dish = Dishes.byId[dishId]
	local world = Worlds.byId[dish.world]
	return Formula.maxAffordable(dish.baseCost, world.costGrowth, Stats.dishLevel(profile, dishId), profile.money)
end

-- Customers / tips ---------------------------------------------------------------

function Stats.tipMultiplier(profile: Profile, speciesId: string): number
	if speciesId == Customers.goldenId then
		return Economy.golden.tipMultiplier
	end
	local species = Customers.byId[speciesId]
	local base = if species then species.tipMultiplier else 1
	return base + Stats.franchiseEffects(profile).tipBonus
end

function Stats.goldenChance(profile: Profile): number
	return Economy.golden.chance * Stats.franchiseEffects(profile).goldenChanceMultiplier
end

-- Tip of a regular (human) customer.
function Stats.humanTip(profile: Profile): number
	return Customers.humanTipMultiplier + Stats.franchiseEffects(profile).tipBonus
end

-- True once the world has a table, so customers sit down and tip more.
function Stats.hasSeating(profile: Profile, worldId: string): boolean
	local builds = profile.builds[worldId]
	if builds then
		for _, kind in builds do
			if kind == "Table" then
				return true
			end
		end
	end
	return false
end

function Stats.seatingMultiplier(profile: Profile, worldId: string): number
	return if Stats.hasSeating(profile, worldId) then Economy.cafe.seatedTipMultiplier else 1
end

-- Staff (or the Auto-Serve pass) pick up cash stacks for you.
function Stats.hasAutoCollect(profile: Profile, worldId: string, ctx: Context): boolean
	return ctx.autoServePass
		or Stats.assignedStaff(profile, worldId, "Waiter") ~= nil
		or Stats.assignedStaff(profile, worldId, "Manager") ~= nil
end

-- Expected tip multiplier of a random customer in a world: mostly people,
-- sometimes a VIP alien (species tip), rarely a Golden Alien. Seating applies.
function Stats.averageTip(profile: Profile, worldId: string): number
	local world = Worlds.byId[worldId]
	local totalWeight, totalTip = 0, 0
	for _, speciesId in world.customers do
		local species = Customers.byId[speciesId]
		local weight = Customers.rarities[species.rarity].weight
		totalWeight += weight
		totalTip += weight * Stats.tipMultiplier(profile, speciesId)
	end
	local alienAverage = if totalWeight > 0 then totalTip / totalWeight else Stats.humanTip(profile)
	local golden = Stats.goldenChance(profile)
	local vip = if totalWeight > 0 then Customers.vipAlienChance else 0
	local average = Stats.humanTip(profile) * (1 - vip - golden)
		+ alienAverage * vip
		+ Economy.golden.tipMultiplier * golden
	return average * Stats.seatingMultiplier(profile, worldId)
end

-- Rates ----------------------------------------------------------------------------

-- Theoretical income/s of a world when every station cooks non-stop and every
-- serving is sold (weather averaged unless ctx.weather is set).
function Stats.worldRate(profile: Profile, ctx: Context, worldId: string): number
	local world = Worlds.byId[worldId]
	local save = profile.worlds[worldId]
	if save == nil or not save.unlocked then
		return 0
	end
	local total = 0
	for _, dishId in world.dishes do
		if Stats.dishLevel(profile, dishId) > 0 then
			local rate = Stats.dishValue(profile, ctx, dishId) / Stats.cookTime(profile, dishId)
			if ctx.weather == nil then
				rate *= Stats.expectedWeatherMultiplier(dishId)
			end
			total += rate
		end
	end
	return total * Stats.averageTip(profile, worldId)
end

-- Income/s a world earns while the player is somewhere else (needs a Manager).
function Stats.backgroundRate(profile: Profile, ctx: Context, worldId: string): number
	if worldId == profile.currentWorld or not Stats.isAutomated(profile, worldId, ctx) then
		return 0
	end
	local efficiency = Stats.backgroundEfficiency(profile, worldId)
	if efficiency <= 0 then
		return 0
	end
	return Stats.worldRate(profile, Stats.defaultContext, worldId)
		* efficiency
		* (if ctx.doubleMoney then Monetization.doubleMoneyMultiplier else 1)
end

function Stats.totalBackgroundRate(profile: Profile, ctx: Context): number
	local total = 0
	for _, world in Worlds.list do
		total += Stats.backgroundRate(profile, ctx, world.id)
	end
	return total
end

-- Offline ----------------------------------------------------------------------------

function Stats.offlineCapSeconds(profile: Profile, ctx: Context): number
	local hours = Economy.offline.baseCapHours + Stats.franchiseEffects(profile).offlineHours
	if ctx.offlinePass then
		hours += Economy.offline.gamePassBonusHours
	end
	return math.min(hours, Economy.offline.maxCapHours) * 3600
end

function Stats.offlineEfficiency(profile: Profile): number
	local director = Stats.assignedStaff(profile, Worlds.first, "Director")
	local efficiency = Economy.offline.efficiency
	if director then
		efficiency += Economy.offline.directorEfficiencyPerRarity * (Stats.rarityMultiplier(director.rarity) - 1)
	end
	return math.min(efficiency, 1)
end

-- Income/s used for offline earnings (before efficiency): the automated world
-- you left from, or every automated world with a Regional Director.
function Stats.offlineRate(profile: Profile, ctx: Context): number
	local director = Stats.assignedStaff(profile, Worlds.first, "Director")
	local passMultiplier = if ctx.doubleMoney then Monetization.doubleMoneyMultiplier else 1
	local total = 0
	for _, world in Worlds.list do
		local counts = director ~= nil or world.id == profile.currentWorld
		if counts and Stats.isAutomated(profile, world.id, ctx) then
			total += Stats.worldRate(profile, Stats.defaultContext, world.id)
		end
	end
	return total * passMultiplier
end

-- Prestige -----------------------------------------------------------------------------

function Stats.starChefGain(profile: Profile): number
	return Formula.starChefsGain(
		profile.lifetimeEarnings,
		profile.totalStarChefs,
		Economy.prestige.divisor,
		Economy.prestige.exponent
	)
end

function Stats.canFranchise(profile: Profile): boolean
	return Stats.starChefGain(profile) >= Economy.prestige.minGain
end

-- Progress -----------------------------------------------------------------------------

local function dishLabel(dishId: string): string
	local dish = Dishes.byId[dishId]
	return dish.icon .. " " .. dish.displayName
end

-- What the "next unlock" bar shows: next dish in the current world, then the
-- next world, then the closest milestone, then the next Star Chef.
function Stats.nextUnlock(profile: Profile): Types.NextUnlock
	local world = Worlds.byId[profile.currentWorld]
	for _, dishId in world.dishes do
		if Stats.dishLevel(profile, dishId) == 0 then
			local cost = Stats.upgradeCost(profile, dishId, 1)
			return {
				kind = "Dish",
				id = dishId,
				label = "Unlock " .. dishLabel(dishId),
				cost = cost,
				progress = Formula.progress(profile.money, cost),
			}
		end
	end

	for _, candidate in Worlds.list do
		local save = profile.worlds[candidate.id]
		if candidate.enabled and save and not save.unlocked then
			return {
				kind = "World",
				id = candidate.id,
				label = "Unlock " .. candidate.displayName,
				cost = candidate.unlockCost,
				progress = Formula.progress(profile.money, candidate.unlockCost),
			}
		end
	end

	local bestDish: string? = nil
	local bestCost = math.huge
	local bestLevel = 0
	for _, dishId in world.dishes do
		local level = Stats.dishLevel(profile, dishId)
		local milestone = Formula.nextMilestone(level, Dishes.milestones)
		if milestone then
			local cost = Stats.upgradeCost(profile, dishId, milestone.level - level)
			if cost < bestCost then
				bestDish, bestCost, bestLevel = dishId, cost, milestone.level
			end
		end
	end
	if bestDish then
		return {
			kind = "Milestone",
			id = bestDish,
			label = dishLabel(bestDish) .. " Lv " .. bestLevel .. " (x2 speed)",
			cost = bestCost,
			progress = Formula.progress(profile.money, bestCost),
		}
	end

	local nextTotal = profile.totalStarChefs + Stats.starChefGain(profile) + 1
	local needed = Formula.earningsForStarChefs(nextTotal, Economy.prestige.divisor, Economy.prestige.exponent)
	return {
		kind = "Franchise",
		id = "StarChef",
		label = "Next Star Chef",
		cost = needed,
		progress = Formula.progress(profile.lifetimeEarnings, needed),
	}
end

return Stats
