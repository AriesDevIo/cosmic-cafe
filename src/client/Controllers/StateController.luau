--!strict
-- Holds the local player's replicated save + context. Read-only on the client:
-- every change goes through a remote and comes back from the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local StateController = {}

StateController.changed = Signal.new() :: Signal.Signal<Types.Profile>
StateController.moneyChanged = Signal.new() :: Signal.Signal<number>
StateController.runtimeChanged = Signal.new() :: Signal.Signal<{ [string]: any }>

local profile: Types.Profile? = nil
local context: Types.Context = {
	doubleMoney = false,
	autoServePass = false,
	offlinePass = false,
	weather = nil,
}
local passes: { [string]: boolean } = {}
local runtime: { [string]: any } = {}
local serverClockOffset = 0 -- os.time() on the server minus os.time() here

function StateController.get(): Types.Profile?
	return profile
end

-- Yields until the first snapshot arrived.
function StateController.wait(): Types.Profile
	while profile == nil do
		task.wait()
	end
	return profile :: Types.Profile
end

function StateController.runtime(): { [string]: any }
	return runtime
end

function StateController.passes(): { [string]: boolean }
	return passes
end

-- Context for Stats calls, with the live weather of the current world.
function StateController.context(): Types.Context
	local weather = nil
	local weatherRuntime = runtime.weather
	if profile and weatherRuntime and weatherRuntime[profile.currentWorld] then
		weather = weatherRuntime[profile.currentWorld].id
	end
	return {
		doubleMoney = context.doubleMoney,
		autoServePass = context.autoServePass,
		offlinePass = context.offlinePass,
		weather = weather,
	}
end

-- Server unix time (for daily resets etc.).
function StateController.serverTime(): number
	return os.time() + serverClockOffset
end

function StateController.start()
	Net.event("State").OnClientEvent:Connect(function(snapshot)
		profile = snapshot.profile
		context = snapshot.context
		passes = snapshot.passes or {}
		serverClockOffset = snapshot.serverTime - os.time()
		StateController.changed:fire(snapshot.profile)
		StateController.moneyChanged:fire(snapshot.profile.money)
	end)
	Net.event("Money").OnClientEvent:Connect(function(money, runEarnings, lifetimeEarnings)
		if profile then
			profile.money = money
			profile.runEarnings = runEarnings
			profile.lifetimeEarnings = lifetimeEarnings
			StateController.moneyChanged:fire(money)
		end
	end)
	Net.event("Runtime").OnClientEvent:Connect(function(values)
		runtime = values
		StateController.runtimeChanged:fire(values)
	end)
	Net.event("Ready"):FireServer()
end

return StateController
