--!strict
-- Tycoon build visuals (client only):
--   * buy pads: price billboard ("Coffee Cart - FREE"), bobbing arrow, green
--     when affordable / red when not, pulsing glow
--   * a freshly bought buildable rises in piece by piece (each part tweens up
--     from below with a little scale pop, staggered), with a dust/confetti
--     puff, build sound and a camera shake for big purchases
-- Models restored on join have BuiltAt = 0 and simply appear.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Buildables = require(Shared.Config.Buildables)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local EffectsController = require(script.Parent.EffectsController)
local StateController = require(script.Parent.StateController)

local BuildFxController = {}

local player = Players.LocalPlayer
local ANIM = Buildables.animation
local PAD = Buildables.pad

type PadView = { pad: BasePart, gui: BillboardGui, price: TextLabel, arrow: Frame }

local padViews: { [BasePart]: PadView } = {}
local animated: { [Model]: boolean } = {}

-- Pads ---------------------------------------------------------------------------------

local function priceText(cost: number): string
	return if cost <= 0 then "FREE" else BigNum.money(cost)
end

local function makePadView(pad: BasePart): PadView
	local gui = Builder.new("BillboardGui", {
		Name = "PadView",
		Size = UDim2.fromOffset(240, 120),
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		MaxDistance = 120,
		LightInfluence = 0,
		AlwaysOnTop = true,
		Adornee = pad,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local panel = Builder.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Theme.colors.panel,
		Parent = gui,
	}, { Builder.corner(UDim.new(0, 16)), Builder.stroke(Theme.colors.outline, 3) })
	Builder.label({
		Text = pad:GetAttribute("DisplayName") :: string,
		Font = Theme.fonts.title,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 26),
		MaxTextSize = 22,
		Parent = panel,
	})
	local price = Builder.label({
		Text = priceText((pad:GetAttribute("Cost") or 0) :: number),
		Font = Theme.fonts.title,
		TextColor3 = Theme.colors.good,
		Position = UDim2.fromOffset(8, 30),
		Size = UDim2.new(1, -16, 0, 24),
		MaxTextSize = 22,
		Parent = panel,
	})
	-- A chunky downward arrow made of a rotated square under a bar.
	local arrow = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(40, 50),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(16, 26),
		BackgroundColor3 = Theme.colors.accent,
		Parent = arrow,
	}, { Builder.stroke(Theme.colors.outline, 3) })
	Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(26, 26),
		Rotation = 45,
		BackgroundColor3 = Theme.colors.accent,
		Parent = arrow,
	}, { Builder.stroke(Theme.colors.outline, 3) })
	return { pad = pad, gui = gui, price = price, arrow = arrow }
end

local function refreshPads()
	local profile = StateController.get()
	local money = if profile then profile.money else 0
	for pad, view in padViews do
		local cost = (pad:GetAttribute("Cost") or 0) :: number
		local affordable = money >= cost
		view.price.TextColor3 = if affordable then Theme.colors.good else Theme.colors.bad
		pad.Color = if affordable then PAD.color else PAD.lockedColor
	end
end

local function trackPad(pad: Instance)
	if not pad:IsA("BasePart") or padViews[pad] then
		return
	end
	if pad:GetAttribute(Map.attributes.Owner) ~= player.UserId then
		return -- only your own pads get price tags
	end
	padViews[pad] = makePadView(pad)
	refreshPads()
end

local function untrackPad(pad: Instance)
	local view = padViews[pad :: BasePart]
	if view then
		view.gui:Destroy()
		padViews[pad :: BasePart] = nil
	end
end

-- Build animation ------------------------------------------------------------------------

local function puff(position: Vector3)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local dust = Builder.new("ParticleEmitter", {
		Rate = 0,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 30),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(230, 215, 190)),
		Acceleration = Vector3.new(0, -10, 0),
		Parent = anchor,
	})
	local confetti = Builder.new("ParticleEmitter", {
		Rate = 0,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(14, 24),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(0.35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
		Acceleration = Vector3.new(0, -30, 0),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.colors.accent),
			ColorSequenceKeypoint.new(0.5, Theme.colors.cyan),
			ColorSequenceKeypoint.new(1, Theme.colors.pink),
		}),
		Parent = anchor,
	})
	dust:Emit(30)
	confetti:Emit(40)
	task.delay(2, function()
		anchor:Destroy()
	end)
end

-- Rises the model in piece by piece (local only; the server CFrames are final).
local function riseIn(model: Model)
	if animated[model] then
		return
	end
	animated[model] = true
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= Map.padSpotName then
			table.insert(parts, descendant)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y -- bottom pieces first
	end)
	for index, part in parts do
		local targetCFrame = part.CFrame
		local targetSize = part.Size
		local targetTransparency = part.Transparency
		part.CFrame = targetCFrame - Vector3.new(0, ANIM.riseFrom, 0)
		part.Transparency = 1
		part.Size = targetSize * 0.6
		task.delay((index - 1) * ANIM.stagger, function()
			if part.Parent == nil then
				return
			end
			local info = TweenInfo.new(ANIM.duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(part, info, {
				CFrame = targetCFrame,
				Transparency = targetTransparency,
				Size = targetSize * ANIM.popScale,
			}):Play()
			task.wait(ANIM.duration)
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.12), { Size = targetSize }):Play()
			end
		end)
	end
	puff(model:GetPivot().Position)
end

local function watchModel(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local builtAt = instance:GetAttribute("BuiltAt")
	if type(builtAt) == "number" and builtAt > 0 and workspace:GetServerTimeNow() - builtAt < 3 then
		-- wait a frame so every part has replicated
		task.defer(riseIn, instance)
	end
end

-- Camera shake -----------------------------------------------------------------------------

local shakeUntil = 0
local shakeStrength = 0

function BuildFxController.shake(strength: number, duration: number)
	shakeStrength = strength
	shakeUntil = os.clock() + duration
end

function BuildFxController.start()
	for _, pad in CollectionService:GetTagged(Map.tags.BuyPad) do
		trackPad(pad)
	end
	CollectionService:GetInstanceAddedSignal(Map.tags.BuyPad):Connect(trackPad)
	CollectionService:GetInstanceRemovedSignal(Map.tags.BuyPad):Connect(untrackPad)
	StateController.moneyChanged:connect(refreshPads)

	workspace.DescendantAdded:Connect(watchModel)

	Net.event("Effect").OnClientEvent:Connect(function(kind, data)
		if kind == "Build" then
			EffectsController.play("Build")
			EffectsController.toast("Built " .. data.name .. "!", "success")
			if data.big then
				BuildFxController.shake(0.35, 0.4)
			end
		end
	end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local bob = math.sin(clock * 4) * 6
		for _, view in padViews do
			view.arrow.Position = UDim2.new(0.5, 0, 0, 64 + bob)
			view.pad.Transparency = 0.15 + (math.sin(clock * 3) + 1) * 0.1
		end
	end)
	-- after the default camera has updated this frame
	RunService:BindToRenderStep("CosmicCafeShake", Enum.RenderPriority.Camera.Value + 1, function()
		if os.clock() < shakeUntil then
			local camera = workspace.CurrentCamera
			local x = (math.random() - 0.5) * shakeStrength
			local y = (math.random() - 0.5) * shakeStrength
			camera.CFrame *= CFrame.new(x, y, 0)
		end
	end)
end

return BuildFxController
