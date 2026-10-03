--!strict
-- Game pass ownership -> Context flags. Pass ids are 0 (stubs) until real
-- passes exist; id 0 is never owned unless Monetization.studioGrantsAll is
-- set while testing in Studio.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Validate = require(Shared.Util.Validate)

local MonetizationService = {}

MonetizationService.changed = Signal.new() :: Signal.Signal<Player>

local owned: { [Player]: { [string]: boolean } } = {}
local checked: { [Player]: boolean } = {} -- every pass has been looked up

local function checkPass(player: Player, passId: string): boolean
	local pass = Monetization.passes[passId]
	if pass.gamePassId == 0 then
		return Monetization.studioGrantsAll and RunService:IsStudio()
	end
	local ok, result =
		pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.gamePassId)
	return ok and result == true
end

function MonetizationService.owns(player: Player, passId: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[passId] == true
end

function MonetizationService.ownedPasses(player: Player): { [string]: boolean }
	return owned[player] or {}
end

-- Yields until the player's passes are known (or `timeout` seconds pass).
function MonetizationService.waitLoaded(player: Player, timeout: number)
	local deadline = os.clock() + timeout
	while not checked[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
end

function MonetizationService.init() end

function MonetizationService.start()
	local function onPlayerAdded(player: Player)
		local passes: { [string]: boolean } = {}
		owned[player] = passes
		for passId in Monetization.passes do
			passes[passId] = checkPass(player, passId)
		end
		checked[player] = true
		MonetizationService.changed:fire(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		checked[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased or owned[player] == nil then
			return
		end
		for passId, pass in Monetization.passes do
			if pass.gamePassId == gamePassId and pass.gamePassId ~= 0 then
				owned[player][passId] = true
				MonetizationService.changed:fire(player)
			end
		end
	end)

	Net.onServerEvent("PromptPass", function(player, passId)
		if not Validate.oneOf(passId, Monetization.passes) then
			return
		end
		local pass = Monetization.passes[passId :: string]
		if pass.gamePassId == 0 then
			Net.fire(player, "Notify", pass.displayName .. " is not on sale yet.", "info")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
	end)
end

return MonetizationService
