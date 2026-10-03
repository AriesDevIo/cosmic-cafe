--!strict
-- Every state change a player can make, as pure functions over a save.
-- The server validates remote arguments and then calls these; the pacing
-- simulator calls the very same functions, so tuning numbers match the game.
-- Randomness is injected (rolls in [0, 1)) to keep everything testable.

local Config = script.Parent.Parent.Config
local DataTemplate = require(Config.DataTemplate)
local Dishes = require(Config.Dishes)
local Economy = require(Config.Economy)
local Franchise = require(Config.Franchise)
local Staff = require(Config.Staff)
local Worlds = require(Config.Worlds)
local Formula = require(script.Parent.Formula)
local Stats = require(script.Parent.Stats)
local TableUtil = require(script.Parent.TableUtil)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile
type Context = Types.Context

local Progression = {}

Progression.MAX_BUY = 1000 -- largest single "buy N" request

-- Money -----------------------------------------------------------------------------

function Progression.earn(profile: Profile, amount: number)
	if amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	profile.money += amount
	profile.runEarnings += amount
	profile.lifetimeEarnings += amount
end

function Progression.trySpend(profile: Profile, amount: number): boolean
	if amount ~= amount or amount < 0 or profile.money < amount then
		return false
	end
	profile.money -= amount
	return true
end

-- Dishes & worlds --------------------------------------------------------------------

-- amount: levels to buy, or 0 for "as many as affordable".
-- Returns (ok, error, levelsBought, cost).
function Progression.buyDish(profile: Profile, dishId: string, amount: number): (boolean, string?, number, number)
	local dish = Dishes.byId[dishId]
	if dish == nil then
		return false, "Unknown dish", 0, 0
	end
	local save = profile.worlds[dish.world]
	if save == nil or not save.unlocked then
		return false, "World locked", 0, 0
	end
	if amount ~= amount or amount < 0 or amount > Progression.MAX_BUY or amount % 1 ~= 0 then
		return false, "Bad amount", 0, 0
	end
	local count = if amount == 0 then math.min(Stats.maxAffordable(profile, dishId), Progression.MAX_BUY) else amount
	if count <= 0 then
		return false, "Not enough money", 0, 0
	end
	local cost = Stats.upgradeCost(profile, dishId, count)
	if not Progression.trySpend(profile, cost) then
		return false, "Not enough money", 0, 0
	end
	save.dishes[dishId] = (save.dishes[dishId] or 0) + count
	return true, nil, count, cost
end

function Progression.unlockWorld(profile: Profile, worldId: string): (boolean, string?)
	local world = Worlds.byId[worldId]
	if world == nil then
		return false, "Unknown world"
	end
	if not world.enabled then
		return false, "Coming soon"
	end
	local save = profile.worlds[worldId]
	if save.unlocked then
		return false, "Already unlocked"
	end
	local previous = Worlds.list[world.index - 1]
	if previous and not profile.worlds[previous.id].unlocked then
		return false, "Unlock " .. previous.displayName .. " first"
	end
	if not Progression.trySpend(profile, world.unlockCost) then
		return false, "Not enough money"
	end
	save.unlocked = true
	local firstDish = world.dishes[1]
	local startLevel = math.max(Economy.startingDishLevel, Stats.franchiseEffects(profile).startDishLevel)
	save.dishes[firstDish] = math.max(save.dishes[firstDish] or 0, startLevel)
	return true, nil
end

function Progression.travel(profile: Profile, worldId: string): (boolean, string?)
	local save = profile.worlds[worldId]
	if save == nil or not save.unlocked then
		return false, "World locked"
	end
	profile.currentWorld = worldId
	return true, nil
end

-- Staff ---------------------------------------------------------------------------------

local function staffCount(profile: Profile): number
	return TableUtil.count(profile.staff.items)
end

function Progression.addStaff(profile: Profile, roleId: string, rarity: string): Types.StaffItem?
	if staffCount(profile) >= Staff.maxInventory then
		return nil
	end
	local id = tostring(profile.staff.nextId)
	profile.staff.nextId += 1
	local item: Types.StaffItem = { id = id, role = roleId, rarity = rarity, assigned = nil }
	profile.staff.items[id] = item
	return item
end

-- Puts a staff member to work in `worldId` (nil = bench). Whoever held the
-- slot before goes to the bench.
function Progression.assignStaff(profile: Profile, staffId: string, worldId: string?): (boolean, string?)
	local item = profile.staff.items[staffId]
	if item == nil then
		return false, "Unknown staff"
	end
	if worldId == nil then
		item.assigned = nil
		return true, nil
	end
	local world = Worlds.byId[worldId]
	if world == nil or not profile.worlds[worldId].unlocked then
		return false, "World locked"
	end
	local slot = Stats.slotKey(worldId, item.role)
	local current = Stats.assignedStaff(profile, worldId, item.role)
	if current and current ~= item then
		current.assigned = nil
	end
	item.assigned = slot
	return true, nil
end

function Progression.canHireRole(profile: Profile, roleId: string): boolean
	local role = Staff.roles[roleId]
	return role ~= nil and Stats.highestWorld(profile).index >= role.unlockWorldIndex
end

-- Hires a Common for an empty slot and puts them to work.
function Progression.hire(profile: Profile, worldId: string, roleId: string): (boolean, string?, Types.StaffItem?)
	local world = Worlds.byId[worldId]
	if world == nil or Staff.roles[roleId] == nil then
		return false, "Unknown world or role", nil
	end
	if not profile.worlds[worldId].unlocked then
		return false, "World locked", nil
	end
	if not Progression.canHireRole(profile, roleId) then
		return false, "Not available yet", nil
	end
	if Stats.assignedStaff(profile, worldId, roleId) then
		return false, "Slot already filled", nil
	end
	if staffCount(profile) >= Staff.maxInventory then
		return false, "Staff room is full", nil
	end
	if not Progression.trySpend(profile, Stats.hireCost(worldId, roleId)) then
		return false, "Not enough money", nil
	end
	local item = Progression.addStaff(profile, roleId, Staff.rarityOrder[1]) :: Types.StaffItem
	Progression.assignStaff(profile, item.id, worldId)
	return true, nil, item
end

function Progression.openCrate(
	profile: Profile,
	crateId: string,
	rarityRoll: number,
	roleRoll: number
): (boolean, string?, Types.StaffItem?)
	local crate = Staff.crates[crateId]
	if crate == nil then
		return false, "Unknown crate", nil
	end
	if staffCount(profile) >= Staff.maxInventory then
		return false, "Staff room is full", nil
	end
	if not Progression.trySpend(profile, Stats.crateCost(profile, crateId)) then
		return false, "Not enough money", nil
	end
	local rarity = Formula.weightedPick(crate.odds, rarityRoll) or Staff.rarityOrder[1]
	local role = Formula.weightedPick(Staff.crateRoleWeights, roleRoll) or Staff.roleOrder[1]
	return true, nil, Progression.addStaff(profile, role, rarity)
end

-- Fuses exactly Staff.fuseCount staff of the same role and rarity into one of
-- the next rarity. If any of them was working, the new one takes that slot.
function Progression.fuse(profile: Profile, staffIds: { string }): (boolean, string?, Types.StaffItem?)
	if #staffIds ~= Staff.fuseCount then
		return false, "Pick " .. Staff.fuseCount .. " staff", nil
	end
	local seen: { [string]: boolean } = {}
	local role: string?, rarity: string? = nil, nil
	local slot: string? = nil
	for _, id in staffIds do
		local item = profile.staff.items[id]
		if item == nil or seen[id] then
			return false, "Invalid staff", nil
		end
		seen[id] = true
		role = role or item.role
		rarity = rarity or item.rarity
		if item.role ~= role or item.rarity ~= rarity then
			return false, "Staff must match role and rarity", nil
		end
		slot = slot or item.assigned
	end
	local nextRarity = Formula.nextRarity(Staff.rarityOrder, rarity :: string)
	if nextRarity == nil then
		return false, "Already max rarity", nil
	end
	for _, id in staffIds do
		profile.staff.items[id] = nil
	end
	local item = Progression.addStaff(profile, role :: string, nextRarity) :: Types.StaffItem
	item.assigned = slot
	return true, nil, item
end

-- Recipes ---------------------------------------------------------------------------------

function Progression.ingredientAvailable(profile: Profile, ingredientId: string): boolean
	local ingredient = Dishes.ingredientById[ingredientId]
	return ingredient ~= nil and profile.worlds[ingredient.world].unlocked
end

function Progression.recipeAttemptCost(profile: Profile, ctx: Context): number
	local rate = Stats.worldRate(profile, ctx, profile.currentWorld)
	return math.max(Economy.recipeLab.minCost, rate * Economy.recipeLab.attemptCostSeconds)
end

function Progression.findRecipe(ingredients: { string }): Dishes.Recipe?
	local key = Formula.recipeKey(ingredients)
	for _, recipe in Dishes.recipes do
		if Formula.recipeKey(recipe.ingredients) == key then
			return recipe
		end
	end
	return nil
end

-- Returns (ok, error, recipe?, isNewDiscovery).
function Progression.combine(
	profile: Profile,
	ctx: Context,
	ingredients: { string }
): (boolean, string?, Dishes.Recipe?, boolean)
	if #ingredients < 2 or #ingredients > Dishes.maxRecipeIngredients then
		return false, "Use 2-" .. Dishes.maxRecipeIngredients .. " ingredients", nil, false
	end
	local seen: { [string]: boolean } = {}
	for _, id in ingredients do
		if seen[id] or not Progression.ingredientAvailable(profile, id) then
			return false, "Invalid ingredient", nil, false
		end
		seen[id] = true
	end
	if not Progression.trySpend(profile, Progression.recipeAttemptCost(profile, ctx)) then
		return false, "Not enough money", nil, false
	end
	local recipe = Progression.findRecipe(ingredients)
	if recipe == nil then
		return true, nil, nil, false
	end
	local isNew = not profile.codex.recipes[recipe.id]
	profile.codex.recipes[recipe.id] = true
	return true, nil, recipe, isNew
end

-- Codex ------------------------------------------------------------------------------------

-- Records a served species; returns true on the first ever serve.
function Progression.recordServe(profile: Profile, speciesId: string): boolean
	local count = profile.codex.species[speciesId] or 0
	profile.codex.species[speciesId] = count + 1
	profile.stats.served += 1
	return count == 0
end

-- Franchise ---------------------------------------------------------------------------------

-- Resets the run, keeping codex, staff, Star Chefs, tree, daily and stats.
function Progression.franchise(profile: Profile): (boolean, string?, number)
	local gain = Stats.starChefGain(profile)
	if gain < Economy.prestige.minGain then
		return false, "Earn more before franchising", 0
	end
	profile.totalStarChefs += gain
	profile.starChefs += gain
	profile.franchiseCount += 1

	local fresh = DataTemplate.new()
	profile.worlds = fresh.worlds
	profile.currentWorld = fresh.currentWorld
	profile.runEarnings = 0
	profile.money = fresh.money

	local effects = Stats.franchiseEffects(profile)
	profile.money += effects.startMoney
	local first = Worlds.byId[Worlds.first]
	local firstDish = first.dishes[1]
	profile.worlds[first.id].dishes[firstDish] =
		math.max(profile.worlds[first.id].dishes[firstDish], effects.startDishLevel)
	return true, nil, gain
end

function Progression.buyFranchiseNode(profile: Profile, nodeId: string): (boolean, string?)
	local node = Franchise.byId[nodeId]
	if node == nil then
		return false, "Unknown upgrade"
	end
	if profile.franchiseNodes[nodeId] then
		return false, "Already owned"
	end
	for _, required in node.requires do
		if not profile.franchiseNodes[required] then
			return false, "Requires " .. Franchise.byId[required].displayName
		end
	end
	if profile.starChefs < node.cost then
		return false, "Not enough Star Chefs"
	end
	profile.starChefs -= node.cost
	profile.franchiseNodes[nodeId] = true
	return true, nil
end

-- Daily ---------------------------------------------------------------------------------------

-- Returns (ok, error, reward, streak).
function Progression.claimDaily(profile: Profile, ctx: Context, now: number): (boolean, string?, number, number)
	local today = Formula.dayIndex(now)
	local graceDays = Economy.daily.streakGraceHours / 24
	local streak, canClaim = Formula.dailyStreak(profile.daily.lastClaimDay, today, profile.daily.streak, graceDays)
	if not canClaim then
		return false, "Already claimed today", 0, profile.daily.streak
	end
	local seconds = Formula.dailyRewardSeconds(
		streak,
		Economy.daily.baseRewardSeconds,
		Economy.daily.perStreakDaySeconds,
		Economy.daily.maxStreakDays
	)
	local reward = math.max(Economy.daily.minReward, Stats.worldRate(profile, ctx, profile.currentWorld) * seconds)
	profile.daily.streak = streak
	profile.daily.lastClaimDay = today
	Progression.earn(profile, reward)
	return true, nil, reward, streak
end

-- Auto-Buy ---------------------------------------------------------------------------------------

-- The single-level dish upgrade in `worldId` with the best payback
-- (cost / added income per second), or nil if nothing is affordable.
function Progression.bestUpgrade(profile: Profile, ctx: Context, worldId: string): (string?, number, number)
	local world = Worlds.byId[worldId]
	local best: string? = nil
	local bestPayback, bestCost = math.huge, 0
	local baseRate = Stats.worldRate(profile, ctx, worldId)
	local save = profile.worlds[worldId]
	for _, dishId in world.dishes do
		local cost = Stats.upgradeCost(profile, dishId, 1)
		if cost <= profile.money then
			local level = save.dishes[dishId]
			save.dishes[dishId] = level + 1
			local gained = Stats.worldRate(profile, ctx, worldId) - baseRate
			save.dishes[dishId] = level
			local payback = if gained > 0 then cost / gained else math.huge
			if payback < bestPayback or (best == nil and payback == math.huge) then
				best, bestPayback, bestCost = dishId, payback, cost
			end
		end
	end
	return best, bestCost, bestPayback
end

return Progression
