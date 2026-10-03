--!strict
-- Daily login streak reward and the daily Food Critic.
--
-- Claiming: once per (UTC) day; consecutive days grow the reward, missing more
-- than the grace period resets the streak (Formula.dailyStreak).
-- Food Critic: once per day a critic shows up in your cafe a little after you
-- join; serving them pays several minutes of income.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)

local CafeService = require(script.Parent.CafeService)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local DailyService = {}

local CRITIC_CHECK_INTERVAL = Economy.daily.criticSpawnDelay

local function today(): number
	return Formula.dayIndex(os.time())
end

local function criticDue(player: Player): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profile.daily.criticDay < today() and not CafeService.hasCriticWaiting(player)
end

function DailyService.init() end

function DailyService.start()
	Net.onServerEvent("ClaimDaily", function(player)
		local profile = DataService.get(player)
		if profile == nil then
			return
		end
		local ok, err, reward, streak = Progression.claimDaily(profile, StateService.context(player), os.time())
		if not ok then
			Net.fire(player, "Notify", err or "Come back tomorrow!", "error")
			return
		end
		StateService.markDirty(player)
		Net.fire(player, "Notify", string.format("📅 Day %d streak! +%s", streak, BigNum.money(reward)), "success")
	end)

	CafeService.criticServed:connect(function(player, reward)
		local profile = DataService.get(player)
		if profile == nil then
			return
		end
		profile.daily.criticDay = today()
		StateService.markDirty(player)
		Net.fire(
			player,
			"Notify",
			"🧐 The Food Critic gave you ⭐⭐⭐⭐⭐ and " .. BigNum.money(reward) .. "!",
			"success"
		)
	end)

	-- After joining (and periodically, in case the critic walked out unserved),
	-- send the critic if today's visit hasn't happened yet.
	task.spawn(function()
		while true do
			task.wait(CRITIC_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				if StateService.isReady(player) and criticDue(player) then
					CafeService.queueCritic(player)
					Net.fire(player, "Notify", "🧐 A Food Critic is on the way to your cafe!", "info")
				end
			end
		end
	end)
end

return DailyService
