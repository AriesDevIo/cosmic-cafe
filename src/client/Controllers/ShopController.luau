--!strict
-- Menu window: buy dish levels (x1 / x10 / Max) for the current world,
-- see milestone progress, toggle Auto-Buy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Dishes = require(Shared.Config.Dishes)
local Formula = require(Shared.Util.Formula)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local StateController = require(script.Parent.StateController)

local ShopController = {}

local AMOUNTS = { { label = "x1", value = 1 }, { label = "x10", value = 10 }, { label = "Max", value = 0 } }

local window: Window.Window
local buyAmount = 1
type Buyable = { button: TextButton, dishId: string }
local buyables: { Buyable } = {}

-- Levels and cost for the selected amount.
local function quote(profile: any, dishId: string): (number, number)
	if buyAmount == 0 then
		local count = Stats.maxAffordable(profile, dishId)
		if count <= 0 then
			return 1, Stats.upgradeCost(profile, dishId, 1)
		end
		return count, Stats.upgradeCost(profile, dishId, count)
	end
	return buyAmount, Stats.upgradeCost(profile, dishId, buyAmount)
end

local function refreshButtons()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	for _, entry in buyables do
		local count, cost = quote(profile, entry.dishId)
		local level = Stats.dishLevel(profile, entry.dishId)
		local verb = if level == 0 then "Unlock" else "Buy x" .. count
		entry.button.Text = verb .. "\n" .. BigNum.money(cost)
		local affordable = cost <= profile.money
		entry.button.BackgroundColor3 = if affordable then Theme.colors.good else Theme.colors.locked
		entry.button.AutoButtonColor = affordable
	end
end

local function dishRow(profile: any, dishId: string, order: number)
	local dish = Dishes.byId[dishId]
	local level = Stats.dishLevel(profile, dishId)
	local ctx = StateController.context()
	local row = Builder.new("Frame", {
		Name = dishId,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = if level > 0 then Theme.colors.panelLight else Theme.colors.panelDark,
		Parent = window.body,
	}, { Builder.corner() })
	Builder.label({
		Text = dish.icon,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(64, 64),
		MaxTextSize = 48,
		Parent = row,
	})
	Builder.label({
		Text = dish.displayName .. (if level > 0 then "  ·  Lv " .. level else "  ·  🔒"),
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 6),
		Size = UDim2.new(1, -230, 0, 28),
		MaxTextSize = 24,
		Parent = row,
	})
	local value = Stats.dishValue(profile, ctx, dishId)
	local cookTime = Stats.cookTime(profile, dishId)
	local detail = if level > 0
		then string.format("%s per serving · %.1fs cook", BigNum.money(value), cookTime)
		else string.format(
			"%s per serving at Lv 1",
			BigNum.money(dish.baseIncome * Stats.incomeMultiplier(profile, ctx))
		)
	Builder.label({
		Text = detail,
		TextColor3 = Theme.colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 34),
		Size = UDim2.new(1, -230, 0, 18),
		MaxTextSize = 16,
		Parent = row,
	})
	local milestone = Formula.nextMilestone(level, Dishes.milestones)
	if milestone and level > 0 then
		local previous = 0
		for _, m in Dishes.milestones do
			if m.level <= level then
				previous = m.level
			end
		end
		local progress = (level - previous) / (milestone.level - previous)
		local bar, fill = Builder.bar({
			Position = UDim2.fromOffset(80, 58),
			Size = UDim2.new(1, -230, 0, 16),
			Parent = row,
		}, Theme.colors.cyan)
		fill.Size = UDim2.fromScale(progress, 1)
		Builder.label({
			Text = string.format("x%g speed at Lv %d", milestone.speedMultiplier, milestone.level),
			Size = UDim2.fromScale(1, 1),
			Font = Theme.fonts.bold,
			TextStrokeTransparency = 0.4,
			MaxTextSize = 12,
			ZIndex = 2,
			Parent = bar,
		})
	end
	local button = Builder.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(130, 60),
		MaxTextSize = 18,
		Parent = row,
	}, function()
		local current = StateController.get()
		if current == nil then
			return
		end
		local _, cost = quote(current, dishId)
		if cost > current.money then
			EffectsController.play("Error")
			return
		end
		EffectsController.play("Buy")
		Net.event("BuyDish"):FireServer(dishId, buyAmount)
	end)
	table.insert(buyables, { button = button, dishId = dishId })
end

local function render()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(window)
	table.clear(buyables)
	local world = Worlds.byId[profile.currentWorld]
	window.title.Text = "🛒 " .. world.displayName .. " Menu"

	local controls = Builder.new("Frame", {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = window.body,
	}, { Builder.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	for index, amount in AMOUNTS do
		Builder.button({
			LayoutOrder = index,
			Text = amount.label,
			Size = UDim2.fromOffset(70, 36),
			BackgroundColor3 = if buyAmount == amount.value then Theme.colors.accent else Theme.colors.panelLight,
			Parent = controls,
		}, function()
			buyAmount = amount.value
			EffectsController.play("Click")
			render()
		end)
	end
	if Stats.franchiseEffects(profile).autoBuy then
		Builder.button({
			LayoutOrder = 10,
			Text = if profile.settings.autoBuy then "🤖 Auto-Buy: ON" else "🤖 Auto-Buy: OFF",
			Size = UDim2.fromOffset(170, 36),
			BackgroundColor3 = if profile.settings.autoBuy then Theme.colors.good else Theme.colors.panelLight,
			Parent = controls,
		}, function()
			Net.event("SetAutoBuy"):FireServer(not profile.settings.autoBuy)
		end)
	end

	for index, dishId in world.dishes do
		dishRow(profile, dishId, index)
	end
	refreshButtons()
end

function ShopController.start()
	window = Window.create("Shop", "🛒 Menu")
	window.render = render
	StateController.changed:connect(function()
		Window.refresh("Shop")
	end)
	StateController.moneyChanged:connect(function()
		if Window.isOpen("Shop") then
			refreshButtons()
		end
	end)
end

return ShopController
