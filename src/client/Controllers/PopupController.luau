--!strict
-- Centered popups that ask for one click: welcome back (offline earnings),
-- daily reward ready, franchise results. Popups queue up one at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Net = require(Shared.Net)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local EffectsController = require(script.Parent.EffectsController)

local PopupController = {}

export type Popup = {
	title: string,
	body: string,
	highlight: string?, -- big golden line (e.g. "+$1.2M")
	button: string,
	onClose: (() -> ())?,
}

local queue: { Popup } = {}
local showing = false
local screen: ScreenGui

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local popup = table.remove(queue, 1) :: Popup
	local dim = Builder.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Parent = screen,
	})
	local panel = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 290),
		BackgroundColor3 = Theme.colors.panel,
		Parent = dim,
	}, {
		Builder.corner(),
		Builder.stroke(Theme.colors.accent, 4),
		Builder.new("UIScale", { Name = "Scale", Scale = 0.3 }),
	})
	Builder.label({
		Text = popup.title,
		Font = Theme.fonts.title,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, 40),
		MaxTextSize = 32,
		Parent = panel,
	})
	Builder.label({
		Text = popup.highlight or "",
		Font = Theme.fonts.title,
		TextColor3 = Theme.colors.gold,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 0, 56),
		MaxTextSize = 48,
		Visible = popup.highlight ~= nil,
		Parent = panel,
	})
	Builder.label({
		Text = popup.body,
		TextColor3 = Theme.colors.textDim,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, if popup.highlight then 124 else 64),
		Size = UDim2.new(1, -40, 0, if popup.highlight then 80 else 140),
		MaxTextSize = 19,
		Parent = panel,
	})
	Builder.button({
		Text = popup.button,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(200, 48),
		BackgroundColor3 = Theme.colors.good,
		MaxTextSize = 24,
		Parent = panel,
	}, function()
		EffectsController.play("Click")
		dim:Destroy()
		showing = false
		if popup.onClose then
			popup.onClose()
		end
		showNext()
	end)
	EffectsController.play("Unlock")
	TweenService:Create(panel:FindFirstChild("Scale") :: UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Scale = 1,
	}):Play()
end

function PopupController.show(popup: Popup)
	table.insert(queue, popup)
	showNext()
end

function PopupController.start()
	screen = Builder.new("ScreenGui", {
		Name = "CosmicCafePopups",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	Net.event("WelcomeBack").OnClientEvent:Connect(function(earned, away, counted, cap)
		local body
		if earned > 0 then
			body = string.format(
				"You were away for %s. Your staff kept cooking for %s%s.",
				BigNum.duration(away),
				BigNum.duration(counted),
				if counted < away then " (cap " .. BigNum.duration(cap) .. ")" else ""
			)
		else
			body = string.format(
				"You were away for %s. Hire a Barista and a Waiter so your cafe earns while you're gone!",
				BigNum.duration(away)
			)
		end
		PopupController.show({
			title = "👋 Welcome back!",
			highlight = if earned > 0 then "+" .. BigNum.money(earned) else nil,
			body = body,
			button = "Collect",
		})
	end)
end

return PopupController
