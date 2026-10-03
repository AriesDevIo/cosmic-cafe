--!strict
-- Offline earnings: when a player rejoins, pay for the time they were away
-- (capped at 2h, upgradable to 12h) from their automated worlds, and show a
-- welcome-back popup. Rules live in Stats/Formula.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StateService = require(script.Parent.StateService)

local OfflineService = {}

-- Seconds away, captured on load before the economy tick refreshes lastOnline.
local pending: { [Player]: number } = {}

function OfflineService.init() end

function OfflineService.start()
	DataService.loaded:connect(function(player, profile)
		local last = profile.offline.lastOnline
		if last > 0 then
			pending[player] = math.max(0, os.time() - last)
		end
	end)

	-- Pay once the client is listening (StateService waits for pass ownership first).
	StateService.ready:connect(function(player, profile)
		local away = pending[player]
		pending[player] = nil
		if away == nil or away < Economy.offline.minSecondsAway then
			return
		end
		local ctx = StateService.context(player)
		local cap = Stats.offlineCapSeconds(profile, ctx)
		local earned, counted =
			Formula.offlineEarnings(Stats.offlineRate(profile, ctx), away, cap, Stats.offlineEfficiency(profile))
		if earned > 0 then
			EconomyService.earn(player, earned)
		end
		Net.fire(player, "WelcomeBack", earned, away, counted, cap)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return OfflineService
