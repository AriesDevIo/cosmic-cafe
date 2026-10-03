--!strict
-- Server-authoritative money: earning, dish purchases, background income from
-- worlds with a Manager, and Auto-Buy. Every rule lives in the shared
-- Progression/Stats modules; this service validates remotes and calls them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dishes = require(Shared.Config.Dishes)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Signal = require(Shared.Util.Signal)
local Stats = require(Shared.Util.Stats)
local Validate = require(Shared.Util.Validate)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local EconomyService = {}

-- (player, dishId) after a dish level changes.
EconomyService.dishChanged = Signal.new() :: Signal.Signal<Player, string>

function EconomyService.context(player: Player)
	return StateService.context(player)
end

function EconomyService.notify(player: Player, text: string, style: string?)
	Net.fire(player, "Notify", text, style or "info")
end

-- Adds money (already multiplied) to a player.
function EconomyService.earn(player: Player, amount: number)
	local profile = DataService.get(player)
	if profile == nil then
		return
	end
	Progression.earn(profile, amount)
	StateService.markDirty(player, "money")
end

-- Spends money; returns false (and changes nothing) if it can't.
function EconomyService.trySpend(player: Player, amount: number): boolean
	local profile = DataService.get(player)
	if profile == nil or not Progression.trySpend(profile, amount) then
		return false
	end
	StateService.markDirty(player, "money")
	return true
end

function EconomyService.buyDish(player: Player, dishId: string, amount: number): boolean
	local profile = DataService.get(player)
	if profile == nil then
		return false
	end
	local before = Stats.dishLevel(profile, dishId)
	local ok, err = Progression.buyDish(profile, dishId, amount)
	if not ok then
		EconomyService.notify(player, err or "Can't buy that", "error")
		return false
	end
	if before == 0 then
		local dish = Dishes.byId[dishId]
		EconomyService.notify(player, dish.icon .. " " .. dish.displayName .. " is on the menu!", "success")
	end
	StateService.markDirty(player)
	EconomyService.dishChanged:fire(player, dishId)
	return true
end

local function autoBuy(player: Player)
	local profile = DataService.get(player)
	if profile == nil or not profile.settings.autoBuy or not Stats.franchiseEffects(profile).autoBuy then
		return
	end
	local ctx = EconomyService.context(player)
	local dishId = Progression.bestUpgrade(profile, ctx, profile.currentWorld)
	if dishId then
		local ok = Progression.buyDish(profile, dishId, 1)
		if ok then
			StateService.markDirty(player)
			EconomyService.dishChanged:fire(player, dishId)
		end
	end
end

function EconomyService.init() end

function EconomyService.start()
	Net.onServerEvent("BuyDish", function(player, dishId, amount)
		if not Validate.oneOf(dishId, Dishes.byId) or not Validate.integer(amount, 0, Progression.MAX_BUY) then
			return
		end
		EconomyService.buyDish(player, dishId :: string, amount :: number)
	end)

	Net.onServerEvent("SetAutoBuy", function(player, enabled)
		local profile = DataService.get(player)
		if profile == nil or not Validate.boolean(enabled) then
			return
		end
		if enabled and not Stats.franchiseEffects(profile).autoBuy then
			EconomyService.notify(player, "Unlock Auto-Buy in the Franchise tree first", "error")
			return
		end
		profile.settings.autoBuy = enabled :: boolean
		StateService.markDirty(player)
	end)

	-- Background worlds, Auto-Buy, play time and the offline timestamp.
	task.spawn(function()
		local sinceAutoBuy = 0
		while true do
			local dt = task.wait(Economy.economyTickInterval)
			sinceAutoBuy += dt
			local doAutoBuy = sinceAutoBuy >= Economy.autoBuy.interval
			if doAutoBuy then
				sinceAutoBuy = 0
			end
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile == nil then
					continue
				end
				local background = Stats.totalBackgroundRate(profile, EconomyService.context(player))
				if background > 0 then
					EconomyService.earn(player, background * dt)
				end
				profile.stats.playSeconds += dt
				profile.offline.lastOnline = os.time()
				if doAutoBuy then
					autoBuy(player)
				end
			end
		end
	end)

	DataService.releasing:connect(function(_player, profile)
		profile.offline.lastOnline = os.time()
	end)
end

return EconomyService
