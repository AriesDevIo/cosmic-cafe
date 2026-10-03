--!strict
-- Codex window (aliens served + recipes discovered) and the Recipe Lab window
-- (pick 2-3 ingredients and combine them to discover recipes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local StateController = require(script.Parent.StateController)

local CodexController = {}

local codexWindow: Window.Window
local labWindow: Window.Window
local picked: { string } = {}

local function heading(window: Window.Window, text: string, order: number)
	Builder.label({
		LayoutOrder = order,
		Text = text,
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 24,
		Parent = window.body,
	})
end

local function grid(window: Window.Window, order: number, cell: Vector2): Frame
	return Builder.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = window.body,
	}, {
		Builder.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(cell.X, cell.Y),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function bonusText(recipe: Dishes.Recipe): string
	if recipe.bonus.globalIncome then
		return string.format("+%d%% all income", recipe.bonus.globalIncome * 100)
	end
	local dish = Dishes.byId[recipe.bonus.dish :: string]
	return string.format("%s x%g value", dish.displayName, recipe.bonus.valueMultiplier or 1)
end

-- Codex ---------------------------------------------------------------------------------

local function renderCodex()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(codexWindow)

	local known = 0
	for _, species in Customers.list do
		if (profile.codex.species[species.id] or 0) > 0 then
			known += 1
		end
	end
	heading(codexWindow, string.format("👽 Aliens %d/%d", known, #Customers.list), 1)
	local aliens = grid(codexWindow, 2, Vector2.new(124, 118))
	for index, species in Customers.list do
		local served = profile.codex.species[species.id] or 0
		local rarity = Customers.rarities[species.rarity]
		local card = Builder.new("Frame", {
			LayoutOrder = index,
			BackgroundColor3 = if served > 0 then Theme.colors.panelLight else Theme.colors.panelDark,
			Parent = aliens,
		}, { Builder.corner(), Builder.stroke(rarity.color, 2) })
		Builder.label({
			Text = if served > 0 then species.icon else "❓",
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = card,
		})
		Builder.label({
			Text = if served > 0 then species.displayName else "???",
			Font = Theme.fonts.bold,
			Position = UDim2.fromOffset(4, 50),
			Size = UDim2.new(1, -8, 0, 20),
			MaxTextSize = 15,
			Parent = card,
		})
		Builder.label({
			Text = species.rarity,
			TextColor3 = rarity.color,
			Position = UDim2.fromOffset(4, 72),
			Size = UDim2.new(1, -8, 0, 16),
			MaxTextSize = 13,
			Parent = card,
		})
		Builder.label({
			Text = if served > 0 then "Served " .. BigNum.format(served) else "Not met yet",
			TextColor3 = Theme.colors.textDim,
			Position = UDim2.fromOffset(4, 92),
			Size = UDim2.new(1, -8, 0, 16),
			MaxTextSize = 12,
			Parent = card,
		})
	end

	local found = 0
	for _, recipe in Dishes.recipes do
		if profile.codex.recipes[recipe.id] then
			found += 1
		end
	end
	heading(codexWindow, string.format("🧪 Recipes %d/%d", found, #Dishes.recipes), 3)
	local recipes = grid(codexWindow, 4, Vector2.new(190, 92))
	for index, recipe in Dishes.recipes do
		local discovered = profile.codex.recipes[recipe.id] == true
		local card = Builder.new("Frame", {
			LayoutOrder = index,
			BackgroundColor3 = if discovered then Theme.colors.panelLight else Theme.colors.panelDark,
			Parent = recipes,
		}, { Builder.corner() })
		local ingredients = {}
		for _, id in recipe.ingredients do
			table.insert(ingredients, if discovered then Dishes.ingredientById[id].icon else "❔")
		end
		Builder.label({
			Text = (if discovered then recipe.icon .. " " .. recipe.displayName else "??? Recipe"),
			Font = Theme.fonts.bold,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 24),
			MaxTextSize = 17,
			Parent = card,
		})
		Builder.label({
			Text = table.concat(ingredients, " + "),
			Position = UDim2.fromOffset(6, 32),
			Size = UDim2.new(1, -12, 0, 24),
			MaxTextSize = 20,
			Parent = card,
		})
		Builder.label({
			Text = if discovered then bonusText(recipe) else #recipe.ingredients .. " ingredients",
			TextColor3 = if discovered then Theme.colors.good else Theme.colors.textDim,
			Position = UDim2.fromOffset(6, 62),
			Size = UDim2.new(1, -12, 0, 20),
			MaxTextSize = 14,
			Parent = card,
		})
	end
end

-- Lab ---------------------------------------------------------------------------------------

local function renderLab()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(labWindow)
	for i = #picked, 1, -1 do
		if not Progression.ingredientAvailable(profile, picked[i]) then
			table.remove(picked, i)
		end
	end

	Builder.label({
		LayoutOrder = 1,
		Text = "Mix 2-3 ingredients. Discoveries boost your income forever, and the first chef on the server to find one gets a badge!",
		TextColor3 = Theme.colors.textDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
		MaxTextSize = 16,
		Parent = labWindow.body,
	})

	local pot = Builder.new("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Theme.colors.panelDark,
		Parent = labWindow.body,
	}, { Builder.corner(), Builder.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	Builder.new("UIPadding", { PaddingTop = UDim.new(0, 10), Parent = pot })
	for slot = 1, Dishes.maxRecipeIngredients do
		local id = picked[slot]
		local ingredient = if id then Dishes.ingredientById[id] else nil
		Builder.button({
			LayoutOrder = slot,
			Text = if ingredient then ingredient.icon else "+",
			Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = if ingredient then Theme.colors.panelLight else Theme.colors.panel,
			MaxTextSize = 38,
			Parent = pot,
		}, function()
			if id then
				table.remove(picked, slot)
				renderLab()
			end
		end)
	end

	local cost = Progression.recipeAttemptCost(profile, StateController.context())
	local canMix = #picked >= 2 and cost <= profile.money
	Builder.button({
		LayoutOrder = 3,
		Text = "🧪 Combine · " .. BigNum.money(cost),
		Size = UDim2.fromOffset(260, 48),
		BackgroundColor3 = if canMix then Theme.colors.accent else Theme.colors.locked,
		MaxTextSize = 22,
		Parent = labWindow.body,
	}, function()
		if not canMix then
			EffectsController.play("Error")
			return
		end
		EffectsController.play("Buy")
		Net.event("Combine"):FireServer(table.clone(picked))
		table.clear(picked)
	end)

	local shelf = grid(labWindow, 4, Vector2.new(96, 86))
	for index, ingredient in Dishes.ingredients do
		local available = Progression.ingredientAvailable(profile, ingredient.id)
		local chosen = table.find(picked, ingredient.id) ~= nil
		local card = Builder.button({
			LayoutOrder = index,
			Text = "",
			BackgroundColor3 = if chosen
				then Theme.colors.accentDark
				elseif available then Theme.colors.panelLight
				else Theme.colors.panelDark,
			AutoButtonColor = available,
			Parent = shelf,
		}, function()
			if not available or chosen or #picked >= Dishes.maxRecipeIngredients then
				return
			end
			EffectsController.play("Click")
			table.insert(picked, ingredient.id)
			renderLab()
		end)
		Builder.label({
			Text = if available then ingredient.icon else "🔒",
			Size = UDim2.new(1, 0, 0, 46),
			Parent = card,
		})
		Builder.label({
			Text = if available then ingredient.displayName else Worlds.byId[ingredient.world].displayName,
			Position = UDim2.fromOffset(2, 50),
			Size = UDim2.new(1, -4, 0, 28),
			TextWrapped = true,
			MaxTextSize = 13,
			Parent = card,
		})
	end
end

function CodexController.start()
	codexWindow = Window.create("Codex", "📖 Codex")
	codexWindow.render = renderCodex
	labWindow = Window.create("Lab", "🧪 Recipe Lab")
	labWindow.render = renderLab
	StateController.changed:connect(function()
		Window.refresh("Codex")
		Window.refresh("Lab")
	end)
end

return CodexController
