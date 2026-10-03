--!strict
-- Worlds window (unlock / travel, background income per world) and the local
-- weather visuals for Cloud City rushes.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local StateController = require(script.Parent.StateController)

local WorldsController = {}

local window: Window.Window

local function worldCard(profile: any, world: Worlds.World)
	local save = profile.worlds[world.id]
	local unlocked = save and save.unlocked
	local here = profile.currentWorld == world.id
	local ctx = StateController.context()
	local card = Builder.new("Frame", {
		LayoutOrder = world.index,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundColor3 = if unlocked then Theme.colors.panelLight else Theme.colors.panelDark,
		Parent = window.body,
	}, { Builder.corner(), Builder.stroke(world.color, if here then 4 else 2) })
	Builder.label({
		Text = string.format("%d. %s%s", world.index, world.displayName, if here then "  📍" else ""),
		Font = Theme.fonts.title,
		TextColor3 = world.color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -190, 0, 30),
		MaxTextSize = 26,
		Parent = card,
	})
	Builder.label({
		Text = world.description,
		TextColor3 = Theme.colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -190, 0, 32),
		MaxTextSize = 15,
		Parent = card,
	})
	if unlocked then
		local status
		if here then
			status = "You are here · " .. BigNum.rate(Stats.worldRate(profile, ctx, world.id))
		else
			local background = Stats.backgroundRate(profile, ctx, world.id)
			status = if background > 0
				then "📋 Manager running it · " .. BigNum.rate(background)
				else "Idle while you're away (hire a Manager + Barista + Waiter)"
		end
		Builder.label({
			Text = status,
			TextColor3 = Theme.colors.cyan,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 72),
			Size = UDim2.new(1, -190, 0, 18),
			MaxTextSize = 14,
			Parent = card,
		})
	end

	local buttonProps = {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 56),
		MaxTextSize = 18,
		Parent = card,
	}
	if not world.enabled then
		buttonProps.Text = "Coming soon"
		buttonProps.BackgroundColor3 = Theme.colors.locked
		buttonProps.AutoButtonColor = false
		Builder.button(buttonProps, function() end)
	elseif unlocked then
		buttonProps.Text = if here then "Here" else "Travel"
		buttonProps.BackgroundColor3 = if here then Theme.colors.locked else Theme.colors.cyan
		Builder.button(buttonProps, function()
			if not here then
				EffectsController.play("Click")
				Net.event("Travel"):FireServer(world.id)
				Window.close("Worlds")
			end
		end)
	else
		local affordable = profile.money >= world.unlockCost
		buttonProps.Text = "Unlock\n" .. BigNum.money(world.unlockCost)
		buttonProps.BackgroundColor3 = if affordable then Theme.colors.good else Theme.colors.locked
		Builder.button(buttonProps, function()
			if affordable then
				EffectsController.play("Unlock")
				Net.event("UnlockWorld"):FireServer(world.id)
				Window.close("Worlds")
			else
				EffectsController.play("Error")
			end
		end)
	end
end

local function render()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(window)
	for _, world in Worlds.list do
		worldCard(profile, world)
	end
end

local function refreshBadge()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local ready = false
	for _, world in Worlds.list do
		if world.enabled and not profile.worlds[world.id].unlocked and profile.money >= world.unlockCost then
			ready = true
		end
	end
	HUDController.setBadge("Worlds", ready)
end

-- Weather visuals ------------------------------------------------------------------

local rainPart: Part? = nil
local tint: ColorCorrectionEffect

local function setWeather(weatherId: string?)
	local camera = workspace.CurrentCamera
	if weatherId == "Rain" and rainPart == nil then
		local part = Builder.new("Part", {
			Name = "CosmicCafeRain",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
			Size = Vector3.new(80, 1, 80),
			Parent = camera,
		})
		Builder.new("ParticleEmitter", {
			Rate = 400,
			Lifetime = NumberRange.new(1, 1.4),
			Speed = NumberRange.new(60, 70),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.12),
			Transparency = NumberSequence.new(0.3),
			Color = ColorSequence.new(Color3.fromRGB(180, 200, 255)),
			LightEmission = 0.3,
			Parent = part,
		})
		rainPart = part
	elseif weatherId ~= "Rain" and rainPart then
		rainPart:Destroy()
		rainPart = nil
	end
	local goal = if weatherId == "Rain"
		then { Brightness = -0.08, Saturation = -0.25, TintColor = Color3.fromRGB(200, 215, 255) }
		elseif weatherId == "Sun" then {
			Brightness = 0.06,
			Saturation = 0.2,
			TintColor = Color3.fromRGB(255, 240, 210),
		}
		else { Brightness = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }
	TweenService:Create(tint, TweenInfo.new(1.5), goal):Play()
end

local currentWeather: string? = nil

local function refreshWeather()
	local profile = StateController.get()
	local weatherRuntime = StateController.runtime().weather
	local state = if profile and weatherRuntime then weatherRuntime[profile.currentWorld] else nil
	local weatherId = if state then state.id else nil
	if weatherId ~= currentWeather then
		currentWeather = weatherId
		setWeather(weatherId)
	end
end

function WorldsController.start()
	window = Window.create("Worlds", "🌍 Worlds")
	window.render = render
	tint = Builder.new("ColorCorrectionEffect", { Name = "CosmicCafeWeather", Parent = Lighting })

	StateController.changed:connect(function()
		Window.refresh("Worlds")
		refreshBadge()
		refreshWeather()
	end)
	StateController.moneyChanged:connect(refreshBadge)
	StateController.runtimeChanged:connect(refreshWeather)

	RunService.RenderStepped:Connect(function()
		if rainPart then
			local camera = workspace.CurrentCamera
			rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
		end
	end)
end

return WorldsController
