--!strict
-- Guided start. Checks each ready player's tutorial step twice a second
-- (Util/Tutorial decides what "done" means), announces new steps and pays the
-- reward + confetti when the last one completes. The client draws the banner,
-- beam and highlight from profile.tutorial.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Tutorial = require(Shared.Util.Tutorial)
local TutorialConfig = require(Shared.Config.Tutorial)

local BuildService = require(script.Parent.BuildService)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

local TutorialService = {}

local CHECK_INTERVAL = 0.5

local function facts(player: Player): Tutorial.Facts
	local plot = WorldService.currentPlot(player)
	-- plots without buildables already have tables
	local hasTables = plot ~= nil and not BuildService.usesBuildables(player, plot.worldId) and #plot.tables > 0
	return { hasTables = hasTables }
end

local function check(player: Player)
	local profile = DataService.get(player)
	if profile == nil or profile.tutorial.done or not StateService.isReady(player) then
		return
	end
	local changed, finished = Tutorial.advance(profile, facts(player))
	if not changed then
		return
	end
	if finished then
		Progression.earn(profile, TutorialConfig.rewardMoney)
		Net.fire(player, "Effect", "TutorialComplete", { reward = TutorialConfig.rewardMoney })
	else
		local step = Tutorial.current(profile)
		if step then
			Net.fire(player, "Effect", "TutorialStep", { id = step.id, index = profile.tutorial.step })
		end
	end
	StateService.markDirty(player)
end

function TutorialService.init() end

function TutorialService.start()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return TutorialService
