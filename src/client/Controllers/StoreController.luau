--!strict
-- Store window: game pass stubs (2x Money, Auto-Serve, +Offline time, VIP
-- decor). Prices/ids live in Config/Monetization; worlds are never sold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Net = require(Shared.Net)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local StateController = require(script.Parent.StateController)

local StoreController = {}

local ORDER = { "DoubleMoney", "AutoServe", "OfflinePlus", "VIPDecor" }
local ICONS = { DoubleMoney = "💰", AutoServe = "🤖", OfflinePlus = "😴", VIPDecor = "👑" }

local window: Window.Window

local function render()
	Window.clear(window)
	local owned = StateController.passes()
	for index, passId in ORDER do
		local pass = Monetization.passes[passId]
		local has = owned[passId] == true
		local card = Builder.new("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 84),
			BackgroundColor3 = Theme.colors.panelLight,
			Parent = window.body,
		}, { Builder.corner(), Builder.stroke(Theme.colors.cyan, 2) })
		Builder.label({
			Text = ICONS[passId] or "💎",
			Position = UDim2.fromOffset(8, 10),
			Size = UDim2.fromOffset(64, 64),
			MaxTextSize = 44,
			Parent = card,
		})
		Builder.label({
			Text = pass.displayName,
			Font = Theme.fonts.title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(80, 10),
			Size = UDim2.new(1, -250, 0, 28),
			MaxTextSize = 24,
			Parent = card,
		})
		Builder.label({
			Text = pass.description,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(80, 40),
			Size = UDim2.new(1, -250, 0, 36),
			MaxTextSize = 15,
			Parent = card,
		})
		Builder.button({
			Text = if has then "✅ Owned" elseif pass.priceRobux > 0 then "R$ " .. pass.priceRobux else "Soon",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(140, 50),
			BackgroundColor3 = if has then Theme.colors.goodDark else Theme.colors.cyan,
			Parent = card,
		}, function()
			if not has then
				EffectsController.play("Click")
				Net.event("PromptPass"):FireServer(passId)
			end
		end)
	end
	Builder.label({
		LayoutOrder = 10,
		Text = "Every world can be unlocked by playing. Passes only add convenience and style.",
		TextColor3 = Theme.colors.textDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 36),
		MaxTextSize = 15,
		Parent = window.body,
	})
end

function StoreController.start()
	window = Window.create("Store", "💎 Store")
	window.render = render
	StateController.changed:connect(function()
		Window.refresh("Store")
	end)
end

return StoreController
