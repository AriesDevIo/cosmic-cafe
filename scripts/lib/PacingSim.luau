--!strict
-- Pacing simulator: a greedy bot plays the real Progression/Stats code with a
-- 1-second time step and records when every unlock happens.
--
-- Model (assumptions are tunable in Economy.sim):
--   * income of the world you're in = Stats.worldRate * a play-style factor
--       - no Barista:  manualEfficiency * averageStreakMultiplier
--       - Barista only: baristaOnlyEfficiency * averageStreakMultiplier
--       - automated:   1 + activeShare * (averageStreakMultiplier - 1)
--   * other worlds pay Stats.totalBackgroundRate (needs a Manager)
--   * the bot buys whatever has the best payback (cost / added income) as long
--     as it pays back within maxPaybackSeconds, and otherwise saves up for the
--     next world (hiring a Manager first so the old world keeps earning).

local Loader = require("../../tests/lib/Loader")

local Dishes = Loader.shared("Config/Dishes")
local Economy = Loader.shared("Config/Economy")
local Franchise = Loader.shared("Config/Franchise")
local Staff = Loader.shared("Config/Staff")
local Worlds = Loader.shared("Config/Worlds")
local Buildables = Loader.shared("Config/Buildables")
local DataTemplate = Loader.shared("Config/DataTemplate")
local Progression = Loader.shared("Util/Progression")
local Stats = Loader.shared("Util/Stats")
local TableUtil = Loader.shared("Util/TableUtil")

local PacingSim = {}

export type Event = {
	time: number, -- seconds since the simulation started
	runTime: number, -- seconds since the current run started
	run: number,
	kind: string,
	text: string,
}

export type Result = {
	events: { Event },
	purchaseTimes: { number }, -- every purchase, total time
	snapshots: { { time: number, money: number, rate: number, run: number } },
	firstSale: number,
	firstHire: number?,
	worldUnlocks: { [string]: { number } }, -- worldId -> runTime per run
	franchises: { { time: number, runTime: number, gain: number } },
	profile: any,
}

type Action = {
	label: string,
	kind: string,
	cost: number,
	apply: (profile: any) -> (),
}

local ctx = Stats.defaultContext

-- Income/s the simulated player makes right now.
function PacingSim.effectiveRate(profile: any): number
	local sim = Economy.sim
	local world = profile.currentWorld
	local rate = Stats.worldRate(profile, ctx, world)
	local factor
	if not Stats.hasAutoCook(profile, world) then
		factor = sim.manualEfficiency * sim.averageStreakMultiplier
	elseif not Stats.hasAutoServe(profile, world, ctx) then
		factor = sim.baristaOnlyEfficiency * sim.averageStreakMultiplier
	else
		factor = 1 + sim.activeShare * (sim.averageStreakMultiplier - 1)
	end
	return rate * factor + Stats.totalBackgroundRate(profile, ctx)
end

local function dishAction(dishId: string, cost: number): Action
	return {
		label = dishId,
		kind = "dish",
		cost = cost,
		apply = function(profile)
			Progression.buyDish(profile, dishId, 1)
		end,
	}
end

local function hireAction(worldId: string, roleId: string): Action
	return {
		label = roleId .. "@" .. worldId,
		kind = "hire",
		cost = Stats.hireCost(worldId, roleId),
		apply = function(profile)
			Progression.hire(profile, worldId, roleId)
		end,
	}
end

-- Generated-lot buildables per world (the sim plays on a generated lot).
local buildDefs: { [string]: { any } } = {}
for _, world in Worlds.list do
	buildDefs[world.id] = (Buildables.forWorld(world.id))
end

-- Buying `def` together with every missing requirement (structures and decor
-- only matter to the bot as gates in front of stations and tables).
local function buildAction(profile: any, worldId: string, def: any): Action
	local byId = {}
	for _, other in buildDefs[worldId] do
		byId[other.id] = other
	end
	local chain: { any } = {}
	local seen: { [string]: boolean } = {}
	local function collect(current: any)
		if seen[current.id] or Progression.ownsBuild(profile, worldId, current.id) then
			return
		end
		seen[current.id] = true
		for _, required in current.requires do
			collect(byId[required])
		end
		table.insert(chain, current)
	end
	collect(def)
	local cost = 0
	for _, item in chain do
		cost += item.cost
	end
	return {
		label = def.displayName,
		kind = "build",
		cost = cost,
		apply = function(target)
			for _, item in chain do
				Progression.buyBuild(target, worldId, item)
			end
		end,
	}
end

-- Every purchase the bot might make (excluding world unlocks).
local function candidateActions(profile: any): { Action }
	local actions: { Action } = {}
	for _, world in Worlds.list do
		if profile.worlds[world.id].unlocked then
			for _, dishId in world.dishes do
				if Stats.dishLevel(profile, dishId) > 0 then
					table.insert(actions, dishAction(dishId, Stats.upgradeCost(profile, dishId, 1)))
				end
			end
			for _, def in buildDefs[world.id] do
				local useful = def.kind == "Station"
					or (def.kind == "Table" and not Stats.hasSeating(profile, world.id))
				if useful and not Progression.ownsBuild(profile, world.id, def.id) then
					table.insert(actions, buildAction(profile, world.id, def))
				end
			end
			for _, roleId in { "Barista", "Waiter" } do
				if Stats.assignedStaff(profile, world.id, roleId) == nil then
					table.insert(actions, hireAction(world.id, roleId))
				end
			end
			if world.id ~= profile.currentWorld and Stats.assignedStaff(profile, world.id, "Manager") == nil then
				table.insert(actions, hireAction(world.id, "Manager"))
			end
		end
	end
	return actions
end

-- Payback (seconds) of an action, by simulating it on a copy.
local function payback(profile: any, action: Action, baseRate: number): number
	local copy = TableUtil.deepCopy(profile)
	copy.money = math.huge
	action.apply(copy)
	local gained = PacingSim.effectiveRate(copy) - baseRate
	if gained <= 0 then
		return math.huge
	end
	return action.cost / gained
end

local function nextWorld(profile: any): any?
	for _, world in Worlds.list do
		if world.enabled and not profile.worlds[world.id].unlocked then
			return world
		end
	end
	return nil
end

function PacingSim.run(options: { seconds: number?, franchiseAt: number? }?): Result
	local opts = options or {}
	local sim = Economy.sim
	local totalSeconds = opts.seconds or sim.runSeconds
	local franchiseAt = opts.franchiseAt or sim.franchiseWhenGainAtLeast

	local profile = DataTemplate.new()
	local result: Result = {
		events = {},
		purchaseTimes = {},
		snapshots = {},
		firstSale = sim.firstBuildSeconds + Dishes.byId[Worlds.list[1].dishes[1]].cookTime + sim.firstServeSeconds,
		firstHire = nil,
		worldUnlocks = {},
		franchises = {},
		profile = profile,
	}

	local time, runStart, run = 0, 0, 1
	local seenDishes: { [string]: boolean } = {}
	local seenMilestones: { [string]: boolean } = {}
	local seenStarChefs = 0
	local seenTens: { [string]: number } = {}

	local function log(kind: string, text: string)
		table.insert(result.events, { time = time, runTime = time - runStart, run = run, kind = kind, text = text })
	end

	local function checkMilestones()
		for _, dish in Dishes.list do
			local level = Stats.dishLevel(profile, dish.id)
			if level > 0 and not seenDishes[dish.id .. run] then
				seenDishes[dish.id .. run] = true
				if time == runStart then
					continue -- starting dish (or Head Start)
				end
				log("dish", "Unlocked " .. dish.displayName)
			end
			local tens = level // 10
			local tensKey = dish.id .. "/" .. run
			if tens > (seenTens[tensKey] or 0) then
				seenTens[tensKey] = tens
				log("goal", dish.displayName .. " Lv " .. tens * 10)
			end
			for _, milestone in Dishes.milestones do
				local key = dish.id .. milestone.level .. "/" .. run
				if level >= milestone.level and not seenMilestones[key] then
					seenMilestones[key] = true
					log("milestone", dish.displayName .. " Lv " .. milestone.level)
				end
			end
		end
	end

	local function buy(action: Action)
		action.apply(profile)
		table.insert(result.purchaseTimes, time)
		if action.kind == "build" and action.label:find("Table") then
			log("build", "Built " .. action.label)
		end
		if action.kind == "hire" then
			if result.firstHire == nil then
				result.firstHire = time
			end
			log("hire", "Hired " .. action.label)
		end
	end

	-- Money needed for the next world (plus a Manager so the old world keeps earning).
	local function worldPlan(): (any?, number, boolean)
		local world = nextWorld(profile)
		if world == nil then
			return nil, 0, false
		end
		local current = profile.currentWorld
		local needManager = Stats.isAutomated(profile, current, ctx)
			and Stats.assignedStaff(profile, current, "Manager") == nil
		local needed = world.unlockCost + if needManager then Stats.hireCost(current, "Manager") else 0
		return world, needed, needManager
	end

	local function tryWorldUnlock(): boolean
		local world, needed, needManager = worldPlan()
		if world == nil or profile.money < needed then
			return false
		end
		if needManager then
			buy(hireAction(profile.currentWorld, "Manager"))
		end
		Progression.unlockWorld(profile, world.id)
		Progression.travel(profile, world.id)
		result.worldUnlocks[world.id] = result.worldUnlocks[world.id] or {}
		table.insert(result.worldUnlocks[world.id], time - runStart)
		log("world", "Unlocked " .. world.displayName)
		return true
	end

	local function shop()
		for _ = 1, 200 do
			if tryWorldUnlock() then
				continue
			end
			local baseRate = PacingSim.effectiveRate(profile)
			local best: Action? = nil
			local bestPayback = math.huge
			for _, action in candidateActions(profile) do
				local seconds = payback(profile, action, baseRate)
				if seconds < bestPayback then
					best, bestPayback = action, seconds
				end
			end
			if best == nil or best.cost > profile.money then
				return
			end
			-- Buy when it pays back quickly, or when buying it still reaches the
			-- next world sooner than saving would.
			local worth = bestPayback <= sim.maxPaybackSeconds
			local world, needed = worldPlan()
			if not worth and world and baseRate > 0 then
				local gained = best.cost / bestPayback
				local remaining = math.max(needed - profile.money, 0)
				worth = (remaining + best.cost) / (baseRate + gained) < remaining / baseRate
			elseif not worth and world == nil then
				worth = true -- nothing left to save for: always grow
			end
			if not worth then
				return
			end
			buy(best)
		end
	end

	local function buyFranchiseNodes()
		local bought = true
		while bought do
			bought = false
			for _, nodeId in sim.franchiseNodeOrder do
				local node = Franchise.byId[nodeId]
				if not profile.franchiseNodes[nodeId] and profile.starChefs >= node.cost then
					if Progression.buyFranchiseNode(profile, nodeId) then
						log("franchise", "Bought tree node " .. node.displayName)
						bought = true
					end
				end
			end
		end
	end

	checkMilestones()
	while time < totalSeconds do
		Progression.earn(profile, PacingSim.effectiveRate(profile) * sim.dt)
		time += sim.dt
		shop()
		checkMilestones()

		local gain = Stats.starChefGain(profile)
		local total = profile.totalStarChefs + gain
		if gain > 0 and total > seenStarChefs and (total == 1 or total % 5 == 0) then
			seenStarChefs = total
			log("starchef", "Franchise would give " .. gain .. " Star Chefs")
		end
		if gain >= math.max(franchiseAt, profile.totalStarChefs * sim.franchiseGainRatio) then
			table.insert(result.franchises, { time = time, runTime = time - runStart, gain = gain })
			Progression.franchise(profile)
			log("franchise", "FRANCHISE #" .. profile.franchiseCount .. " for " .. gain .. " Star Chefs")
			run += 1
			runStart = time
			buyFranchiseNodes()
			checkMilestones()
		end

		if time % sim.snapshotEvery == 0 then
			table.insert(
				result.snapshots,
				{ time = time, money = profile.money, rate = PacingSim.effectiveRate(profile), run = run }
			)
		end
	end
	return result
end

local GOAL_KINDS = { dish = true, hire = true, world = true, goal = true, milestone = true, build = true }

-- Seconds between goals (new dish, hire, world, milestone, every 10th level)
-- inside [from, to). Several goals in the same second count once.
function PacingSim.goalGaps(result: Result, from: number, to: number): { number }
	local gaps = {}
	local last = from
	for _, event in result.events do
		if GOAL_KINDS[event.kind] and event.time >= from and event.time < to and event.time > last then
			table.insert(gaps, event.time - last)
			last = event.time
		end
	end
	return gaps
end

-- Staff config is referenced so the sim fails loudly if roles are renamed.
assert(Staff.roles.Barista and Staff.roles.Waiter and Staff.roles.Manager, "PacingSim expects these roles")

return PacingSim
