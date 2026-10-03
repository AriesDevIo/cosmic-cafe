--!strict
-- Franchise (prestige): reset money, dish levels and worlds for Star Chefs.
-- Codex, staff, Star Chefs, the Franchise tree, daily streak and stats are
-- kept (Progression.franchise). Star Chefs give +income each and are spent
-- on Franchise tree nodes (Auto-Buy, offline time, head starts...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Franchise = require(Shared.Config.Franchise)
local Monetization = require(Shared.Config.Monetization)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Validate = require(Shared.Util.Validate)
local Worlds = require(Shared.Config.Worlds)

local CodexService = require(script.Parent.CodexService)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

local PrestigeService = {}

function PrestigeService.init() end

function PrestigeService.start()
	Net.onServerEvent("Franchise", function(player)
		local profile = DataService.get(player)
		if profile == nil then
			return
		end
		local ok, err, gain = Progression.franchise(profile)
		if not ok then
			Net.fire(player, "Notify", err or "Not yet!", "error")
			return
		end
		if profile.franchiseCount == 1 then
			CodexService.awardBadge(player, Monetization.badges.FirstFranchise)
		end
		StateService.markDirty(player)
		-- Back to the first world with a fresh cafe.
		WorldService.travel(player, Worlds.first)
		Net.fire(player, "Effect", "Franchise", { gain = gain, total = profile.totalStarChefs })
		Net.fireAll(
			"Announce",
			string.format(
				"⭐ %s opened franchise #%d and earned %d Star Chefs!",
				player.DisplayName,
				profile.franchiseCount,
				gain
			),
			"#FFE26E"
		)
	end)

	Net.onServerEvent("BuyNode", function(player, nodeId)
		local profile = DataService.get(player)
		if profile == nil or not Validate.oneOf(nodeId, Franchise.byId) then
			return
		end
		local ok, err = Progression.buyFranchiseNode(profile, nodeId :: string)
		if not ok then
			Net.fire(player, "Notify", err or "Can't buy that", "error")
			return
		end
		local node = Franchise.byId[nodeId :: string]
		Net.fire(player, "Notify", node.icon .. " " .. node.displayName .. " unlocked!", "success")
		StateService.markDirty(player)
	end)
end

return PrestigeService
