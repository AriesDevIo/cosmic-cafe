--!strict
-- Codex: alien species served and recipes discovered.
-- Rare species and the Golden Alien are announced to the whole server, and the
-- first player on a server to discover a recipe gets a badge + announcement.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Monetization = require(Shared.Config.Monetization)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Validate = require(Shared.Util.Validate)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local CodexService = {}

-- recipeId -> UserId of the first discoverer on this server
local serverFirsts: { [string]: number } = {}

local function colorHex(color: Color3): string
	return "#" .. color:ToHex()
end

function CodexService.awardBadge(player: Player, badgeId: number)
	if badgeId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
		if not ok then
			warn("[CodexService] badge award failed: " .. tostring(err))
		end
	end)
end

-- Called by CafeService after every serve.
function CodexService.recordServe(player: Player, speciesId: string, earned: number)
	local profile = DataService.get(player)
	local species = Customers.byId[speciesId]
	if profile == nil or species == nil then
		return
	end
	local first = Progression.recordServe(profile, speciesId)
	local rarity = Customers.rarities[species.rarity]
	if first then
		Net.fire(player, "Discovery", "Species", speciesId, false)
		StateService.markDirty(player)
	end
	if speciesId == Customers.goldenId then
		profile.stats.goldenServed += 1
		CodexService.awardBadge(player, Monetization.badges.GoldenAlien)
		Net.fireAll(
			"Announce",
			string.format("🏆 %s served a GOLDEN ALIEN for %s!", player.DisplayName, BigNum.money(earned)),
			colorHex(rarity.color)
		)
	elseif rarity.announce and speciesId ~= Customers.criticId then
		Net.fireAll(
			"Announce",
			string.format(
				"%s %s served a %s %s!",
				species.icon,
				player.DisplayName,
				species.rarity,
				species.displayName
			),
			colorHex(rarity.color)
		)
	end
end

function CodexService.init() end

function CodexService.start()
	Net.onServerEvent("Combine", function(player, ingredients)
		local profile = DataService.get(player)
		if profile == nil or not Validate.stringArray(ingredients, Dishes.maxRecipeIngredients, 32) then
			return
		end
		local list = ingredients :: { string }
		local ctx = StateService.context(player)
		local ok, err, recipe, isNew = Progression.combine(profile, ctx, list)
		StateService.markDirty(player)
		if not ok then
			Net.fire(player, "Notify", err or "Can't combine that", "error")
			return
		end
		if recipe == nil then
			Net.fire(player, "Notify", "Nothing happened... try another combination!", "info")
			Net.fire(player, "Effect", "RecipeFail", {})
			return
		end
		if not isNew then
			Net.fire(player, "Notify", recipe.icon .. " You already know " .. recipe.displayName, "info")
			return
		end
		local firstOnServer = serverFirsts[recipe.id] == nil
		if firstOnServer then
			serverFirsts[recipe.id] = player.UserId
			CodexService.awardBadge(player, Monetization.badges.FirstDiscovery)
			Net.fireAll(
				"Announce",
				string.format(
					"🧪 %s discovered %s %s first on this server!",
					player.DisplayName,
					recipe.icon,
					recipe.displayName
				),
				"#FFD66B"
			)
		end
		Net.fire(player, "Discovery", "Recipe", recipe.id, firstOnServer)
	end)
end

return CodexService
