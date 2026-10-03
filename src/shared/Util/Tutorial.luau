--!strict
-- Tutorial progression as pure functions over the save.

local Config = script.Parent.Parent.Config
local Staff = require(Config.Staff)
local TutorialConfig = require(Config.Tutorial)
local Worlds = require(Config.Worlds)
local Stats = require(script.Parent.Stats)
local Types = require(script.Parent.Parent.Types)

type Profile = Types.Profile

-- Things the save alone can't tell (the plot the player is on).
export type Facts = {
	hasTables: boolean, -- the current plot has tables without buying (no buildables)
}

local Tutorial = {}

Tutorial.defaultFacts = table.freeze({ hasTables = false }) :: Facts

function Tutorial.current(profile: Profile): TutorialConfig.Step?
	if profile.tutorial.done then
		return nil
	end
	return TutorialConfig.steps[profile.tutorial.step]
end

local function firstWorldDish(slot: number): string?
	return Worlds.byId[Worlds.first].dishes[slot]
end

function Tutorial.isComplete(profile: Profile, step: TutorialConfig.Step, facts: Facts): boolean
	local id = step.id
	if id == "BuildFirstStation" or id == "BuySecondStation" then
		local dishId = firstWorldDish(step.padDishSlot or 1)
		return dishId ~= nil and Stats.dishLevel(profile, dishId) > 0
	elseif id == "ServeFirst" then
		return profile.stats.served > 0
	elseif id == "CollectCash" then
		return profile.stats.cashCollected > 0
	elseif id == "BuyTable" then
		return facts.hasTables or Stats.hasSeating(profile, Worlds.first)
	elseif id == "HireBarista" then
		for _, item in profile.staff.items do
			if item.role == Staff.roles.Barista.id then
				return true
			end
		end
		return false
	end
	return true
end

-- Moves past every completed step. Returns (changed, justFinished).
-- The caller pays TutorialConfig.rewardMoney when justFinished is true.
function Tutorial.advance(profile: Profile, facts: Facts): (boolean, boolean)
	if profile.tutorial.done then
		return false, false
	end
	local changed = false
	while true do
		local step = TutorialConfig.steps[profile.tutorial.step]
		if step == nil then
			profile.tutorial.done = true
			return true, true
		end
		if not Tutorial.isComplete(profile, step, facts) then
			return changed, false
		end
		profile.tutorial.step += 1
		changed = true
	end
end

-- Should the HUD show this menu button yet?
function Tutorial.menuVisible(profile: Profile, menuId: string): boolean
	local rule = TutorialConfig.menus[menuId]
	if rule == nil then
		return true
	end
	local done = profile.tutorial.done
	if rule.step and not done and profile.tutorial.step < rule.step then
		return false
	end
	if rule.afterTutorial and not done then
		return false
	end
	if rule.worldsAtUnlockFraction then
		local nextWorld = Worlds.list[2]
		local unlocked = nextWorld == nil or profile.worlds[nextWorld.id].unlocked
		-- lifetime earnings never go down, so the button never disappears again
		if not unlocked and profile.lifetimeEarnings < nextWorld.unlockCost * rule.worldsAtUnlockFraction then
			return false
		end
	end
	if rule.franchise and profile.franchiseCount == 0 and not Stats.canFranchise(profile) then
		return false
	end
	return true
end

return Tutorial
