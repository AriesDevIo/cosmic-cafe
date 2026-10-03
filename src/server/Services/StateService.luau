--!strict
-- Replicates each player's own save to their client.
--
-- The client gets the whole profile plus the Context (passes, weather) and runs
-- the shared Stats module itself for display, so the server only has to send
-- raw state. Services call markDirty(player) after a change; a cheap "Money"
-- update is sent when only money moved, a full "State" otherwise. Pushes are
-- throttled to Economy.stateSyncInterval.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

type Profile = Types.Profile

local StateService = {}

-- Fired once per join when the client is ready and the profile is loaded.
StateService.ready = Signal.new() :: Signal.Signal<Player, Profile>

type Dirty = "money" | "full"

local dirty: { [Player]: Dirty } = {}
local readyPlayers: { [Player]: boolean } = {}
local weatherProvider: (worldId: string) -> string? = function(_worldId: string): string?
	return nil
end
local runtimeProviders: { [string]: (player: Player) -> any } = {}

function StateService.setWeatherProvider(provider: (worldId: string) -> string?)
	weatherProvider = provider
end

-- Runtime values that aren't saved (tip streak, weather timers...).
function StateService.addRuntimeProvider(name: string, provider: (player: Player) -> any)
	runtimeProviders[name] = provider
end

function StateService.context(player: Player): Types.Context
	local profile = DataService.get(player)
	return {
		doubleMoney = MonetizationService.owns(player, "DoubleMoney"),
		autoServePass = MonetizationService.owns(player, "AutoServe"),
		offlinePass = MonetizationService.owns(player, "OfflinePlus"),
		weather = if profile then weatherProvider(profile.currentWorld) else nil,
	}
end

function StateService.isReady(player: Player): boolean
	return readyPlayers[player] == true
end

function StateService.markDirty(player: Player, kind: Dirty?)
	local wanted: Dirty = kind or "full"
	if dirty[player] ~= "full" then
		dirty[player] = wanted
	end
end

local function runtime(player: Player): { [string]: any }
	local values = {}
	for name, provider in runtimeProviders do
		values[name] = provider(player)
	end
	return values
end

function StateService.pushRuntime(player: Player)
	if readyPlayers[player] then
		Net.fire(player, "Runtime", runtime(player), workspace:GetServerTimeNow())
	end
end

local function flush(player: Player, kind: Dirty)
	local profile = DataService.get(player)
	if profile == nil or not readyPlayers[player] then
		return
	end
	if kind == "money" then
		Net.fire(player, "Money", profile.money, profile.runEarnings, profile.lifetimeEarnings)
	else
		Net.fire(player, "State", {
			profile = profile,
			context = StateService.context(player),
			serverTime = os.time(),
			passes = MonetizationService.ownedPasses(player),
		})
	end
end

function StateService.init() end

function StateService.start()
	Net.onServerEvent("Ready", function(player)
		if readyPlayers[player] then
			return
		end
		local profile = DataService.waitFor(player)
		if profile == nil then
			return
		end
		readyPlayers[player] = true
		flush(player, "full")
		StateService.pushRuntime(player)
		StateService.ready:fire(player, profile)
	end)

	MonetizationService.changed:connect(function(player)
		StateService.markDirty(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		readyPlayers[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Economy.stateSyncInterval)
			local batch = dirty
			dirty = {}
			for player, kind in batch do
				flush(player, kind)
			end
		end
	end)
end

return StateService
