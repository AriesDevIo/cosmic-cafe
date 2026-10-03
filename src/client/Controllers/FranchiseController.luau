--!strict
-- Franchise window: Star Chef bonus, franchise preview + confirm, and the
-- Franchise tree.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Franchise = require(Shared.Config.Franchise)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local PopupController = require(script.Parent.PopupController)
local StateController = require(script.Parent.StateController)

local FranchiseController = {}

local window: Window.Window
local PRESTIGE = Economy.prestige

local function bonusPercent(starChefs: number): number
	return math.floor(starChefs * PRESTIGE.incomeBonusPerStarChef * 100 + 0.5)
end

local function confirmFranchise(gain: number)
	PopupController.show({
		title = "⭐ Open a franchise?",
		highlight = string.format("+%d Star Chefs", gain),
		body = "Resets money, dish levels and worlds. You keep your staff, Codex, recipes, Star Chefs and tree.",
		button = "Franchise!",
		cancel = "Not yet",
		onClose = function()
			Net.event("Franchise"):FireServer()
			Window.close("Franchise")
		end,
	})
end

local function nodeCard(profile: any, node: Franchise.Node, order: number, parent: Instance)
	local owned = profile.franchiseNodes[node.id] == true
	local missing: { string } = {}
	for _, required in node.requires do
		if not profile.franchiseNodes[required] then
			table.insert(missing, Franchise.byId[required].displayName)
		end
	end
	local affordable = profile.starChefs >= node.cost and #missing == 0 and not owned
	local card = Builder.new("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = if owned then Theme.colors.goodDark else Theme.colors.panelLight,
		Parent = parent,
	}, { Builder.corner(), Builder.stroke(if owned then Theme.colors.good else Theme.colors.star, 2) })
	Builder.label({
		Text = node.icon .. " " .. node.displayName,
		Font = Theme.fonts.bold,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -16, 0, 22),
		MaxTextSize = 17,
		Parent = card,
	})
	Builder.label({
		Text = node.description,
		TextColor3 = Theme.colors.textDim,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, 30),
		Size = UDim2.new(1, -16, 0, 36),
		MaxTextSize = 14,
		Parent = card,
	})
	local text
	if owned then
		text = "✅ Owned"
	elseif #missing > 0 then
		text = "Needs " .. table.concat(missing, ", ")
	else
		text = string.format("⭐ %d", node.cost)
	end
	Builder.button({
		Text = text,
		Position = UDim2.new(0, 8, 1, -40),
		Size = UDim2.new(1, -16, 0, 32),
		BackgroundColor3 = if affordable then Theme.colors.accent else Theme.colors.locked,
		AutoButtonColor = affordable,
		MaxTextSize = 16,
		Parent = card,
	}, function()
		if affordable then
			EffectsController.play("Buy")
			Net.event("BuyNode"):FireServer(node.id)
		end
	end)
end

local function render()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(window)
	local gain = Stats.starChefGain(profile)

	local summary = Builder.new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 88),
		BackgroundColor3 = Theme.colors.panelLight,
		Parent = window.body,
	}, { Builder.corner(), Builder.stroke(Theme.colors.star, 2) })
	Builder.label({
		Text = string.format(
			"⭐ %d Star Chefs  ·  +%d%% income",
			profile.totalStarChefs,
			bonusPercent(profile.totalStarChefs)
		),
		Font = Theme.fonts.title,
		TextColor3 = Theme.colors.star,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 34),
		MaxTextSize = 26,
		Parent = summary,
	})
	Builder.label({
		Text = string.format(
			"%d unspent for the tree  ·  %d franchise%s opened",
			profile.starChefs,
			profile.franchiseCount,
			if profile.franchiseCount == 1 then "" else "s"
		),
		TextColor3 = Theme.colors.textDim,
		Position = UDim2.fromOffset(12, 48),
		Size = UDim2.new(1, -24, 0, 26),
		MaxTextSize = 17,
		Parent = summary,
	})

	-- Franchise now
	local nextTotal = profile.totalStarChefs + gain + 1
	local needed = Formula.earningsForStarChefs(nextTotal, PRESTIGE.divisor, PRESTIGE.exponent)
	local bar, fill = Builder.bar({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = window.body,
	}, Theme.colors.star)
	fill.Size = UDim2.fromScale(Formula.progress(profile.lifetimeEarnings, needed), 1)
	Builder.label({
		Text = string.format("Next Star Chef at %s lifetime earnings", BigNum.money(needed)),
		Size = UDim2.fromScale(1, 1),
		Font = Theme.fonts.bold,
		TextStrokeTransparency = 0.4,
		MaxTextSize = 15,
		ZIndex = 2,
		Parent = bar,
	})
	local canFranchise = gain >= PRESTIGE.minGain
	Builder.button({
		LayoutOrder = 3,
		Text = if canFranchise
			then string.format("⭐ Franchise for +%d Star Chefs (+%d%% income)", gain, bonusPercent(gain))
			else "Earn more to open your first franchise",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = if canFranchise then Theme.colors.accent else Theme.colors.locked,
		MaxTextSize = 22,
		Parent = window.body,
	}, function()
		if canFranchise then
			confirmFranchise(gain)
		else
			EffectsController.play("Error")
		end
	end)

	Builder.label({
		LayoutOrder = 4,
		Text = "Franchise tree",
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 24,
		Parent = window.body,
	})
	local tree = Builder.new("Frame", {
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = window.body,
	}, {
		Builder.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(212, 116),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, node in Franchise.nodes do
		nodeCard(profile, node, index, tree)
	end
end

local function refreshBadge()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local gain = Stats.starChefGain(profile)
	-- nudge once a franchise would at least double the current bonus
	HUDController.setBadge("Franchise", gain >= math.max(PRESTIGE.minGain, profile.totalStarChefs))
end

function FranchiseController.start()
	window = Window.create("Franchise", "⭐ Franchise")
	window.render = render
	StateController.changed:connect(function()
		Window.refresh("Franchise")
		refreshBadge()
	end)
	StateController.moneyChanged:connect(refreshBadge)
	Net.event("Effect").OnClientEvent:Connect(function(kind, data)
		if kind == "Franchise" then
			PopupController.show({
				title = "⭐ Franchise opened!",
				highlight = string.format("+%d Star Chefs", data.gain),
				body = string.format(
					"You now have %d Star Chefs (+%d%% income). Spend them in the Franchise tree!",
					data.total,
					bonusPercent(data.total)
				),
				button = "Let's cook",
			})
		end
	end)
end

return FranchiseController
