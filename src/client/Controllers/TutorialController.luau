--!strict
-- Tutorial guidance: one big banner at the top, a Beam from the player to the
-- current target and a pulsing Highlight on it. Targets come from
-- Config/Tutorial (a buy pad, a customer or station, a cash stack, or a HUD
-- menu button which pulses instead).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Map = require(Shared.Config.Map)
local Net = require(Shared.Net)
local Tutorial = require(Shared.Util.Tutorial)
local TutorialConfig = require(Shared.Config.Tutorial)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local PopupController = require(script.Parent.PopupController)
local StateController = require(script.Parent.StateController)

local TutorialController = {}

local player = Players.LocalPlayer
local OWNER = Map.attributes.Owner

local banner: Frame
local stepLabel: TextLabel
local titleLabel: TextLabel
local detailLabel: TextLabel
local beam: Beam
local targetAttachment: Attachment
local highlight: Highlight
local pulsingMenu: string? = nil
local currentStepId: string? = nil

local function isMine(instance: Instance): boolean
	return instance:GetAttribute(OWNER) == player.UserId
end

local function partOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Target lookup ------------------------------------------------------------------------

local function findPad(step: TutorialConfig.Step, worldId: string): Instance?
	local wantedDish = if step.padDishSlot then Worlds.byId[worldId].dishes[step.padDishSlot] else nil
	for _, pad in CollectionService:GetTagged(Map.tags.BuyPad) do
		if isMine(pad) and pad:GetAttribute("Kind") == step.padKind then
			if wantedDish == nil or pad:GetAttribute("Dish") == wantedDish then
				return pad
			end
		end
	end
	return nil
end

local function myStations(): { BasePart }
	local list = {}
	for _, part in CollectionService:GetTagged(Map.tags.ActiveStation) do
		if part:IsA("BasePart") and isMine(part) then
			table.insert(list, part)
		end
	end
	return list
end

-- Serve step: a waiting customer whose dish is ready, else the station to cook at.
local function findServeTarget(): (Instance?, string)
	local stations = myStations()
	local ready: { [string]: boolean } = {}
	for _, station in stations do
		if ((station:GetAttribute("Ready") or 0) :: number) > 0 then
			ready[station:GetAttribute("Dish") :: string] = true
		end
	end
	for _, customer in CollectionService:GetTagged(Map.tags.Customer) do
		if isMine(customer) and customer:GetAttribute("Queued") and ready[customer:GetAttribute("Order") :: string] then
			return customer, "Tap the customer to serve!"
		end
	end
	local station = stations[1]
	if station then
		local cooking = station:GetAttribute("Cooking") == true
		return station, if cooking then "Cooking..." else "Tap Cook at the cart!"
	end
	return nil, ""
end

local function findCash(): Instance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best, bestDistance = nil, math.huge
	for _, cash in CollectionService:GetTagged(Map.tags.CashStack) do
		local part = partOf(cash)
		if part and isMine(cash) then
			local distance = if root then (part.Position - root.Position).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = cash, distance
			end
		end
	end
	return best
end

local function resolveTarget(step: TutorialConfig.Step, worldId: string): (Instance?, string?)
	if step.target == "Pad" then
		return findPad(step, worldId), nil
	elseif step.target == "Customer" then
		return findServeTarget()
	elseif step.target == "Cash" then
		return findCash(), nil
	end
	return nil, nil
end

-- Banner -----------------------------------------------------------------------------------

local function build()
	local screen = Builder.new("ScreenGui", {
		Name = "CosmicCafeTutorial",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Scale.attach(screen)
	banner = Builder.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(560, 92),
		BackgroundColor3 = Theme.colors.accent,
		Visible = false,
		Parent = screen,
	}, {
		Builder.corner(UDim.new(0, 20)),
		Builder.stroke(Theme.colors.outline, 4),
		Builder.gradient(),
		Builder.new("UIScale", { Name = "Pop", Scale = 1 }),
	})
	stepLabel = Builder.label({
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Theme.fonts.title,
		TextColor3 = Theme.colors.outline,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = banner,
	})
	titleLabel = Builder.label({
		Position = UDim2.fromOffset(16, 22),
		Size = UDim2.new(1, -32, 0, 38),
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 34,
		Outlined = true,
		Parent = banner,
	})
	detailLabel = Builder.label({
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 0, 22),
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Outlined = true,
		Parent = banner,
	})

	targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "TutorialTarget"
	targetAttachment.Parent = workspace.Terrain
	beam = Builder.new("Beam", {
		Name = "TutorialBeam",
		Attachment1 = targetAttachment,
		Color = ColorSequence.new(Theme.colors.accent, Theme.colors.good),
		Width0 = 1.2,
		Width1 = 0.4,
		FaceCamera = true,
		Segments = 20,
		CurveSize0 = 6,
		LightEmission = 0.6,
		Transparency = NumberSequence.new(0.15),
		Enabled = false,
		Parent = workspace.Terrain,
	})
	highlight = Builder.new("Highlight", {
		Name = "TutorialHighlight",
		FillColor = Theme.colors.accent,
		OutlineColor = Color3.new(1, 1, 1),
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

local function popBanner()
	local pop = banner:FindFirstChild("Pop") :: UIScale
	pop.Scale = 0.6
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function setMenuPulse(menu: string?)
	if pulsingMenu == menu then
		return
	end
	if pulsingMenu then
		HUDController.pulse(pulsingMenu, false)
	end
	pulsingMenu = menu
	if menu then
		HUDController.pulse(menu, true)
	end
end

local function attachBeamToCharacter()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		beam.Attachment0 = nil
		return
	end
	local attachment = root:FindFirstChild("TutorialSource") :: Attachment?
	if attachment == nil then
		local created = Instance.new("Attachment")
		created.Name = "TutorialSource"
		created.Parent = root
		attachment = created
	end
	beam.Attachment0 = attachment
end

local function update()
	local profile = StateController.get()
	local step = if profile then Tutorial.current(profile) else nil
	if profile == nil or step == nil then
		banner.Visible = false
		beam.Enabled = false
		highlight.Enabled = false
		setMenuPulse(nil)
		return
	end
	if step.id ~= currentStepId then
		currentStepId = step.id
		banner.Visible = true
		popBanner()
	end
	stepLabel.Text = string.format("STEP %d / %d", profile.tutorial.step, #TutorialConfig.steps)
	titleLabel.Text = step.title

	local target, hint = resolveTarget(step, profile.currentWorld)
	detailLabel.Text = if hint and hint ~= "" then hint else step.detail
	setMenuPulse(if step.target == "Menu" then step.menu else nil)

	local part = if target then partOf(target) else nil
	if part then
		attachBeamToCharacter()
		targetAttachment.WorldPosition = part.Position + Vector3.new(0, 2, 0)
		beam.Enabled = beam.Attachment0 ~= nil
		highlight.Adornee = target
		highlight.Enabled = true
	else
		beam.Enabled = false
		highlight.Enabled = false
	end
end

local function onEffect(kind: string, data: any)
	if kind == "TutorialStep" then
		EffectsController.play("Unlock")
	elseif kind == "TutorialComplete" then
		EffectsController.confetti()
		EffectsController.play("Unlock")
		PopupController.show({
			title = "You're a cafe owner!",
			highlight = "+" .. BigNum.money(data.reward),
			body = "Your Barista cooks for you now. Keep building your lot, upgrade dishes in the Menu and check the Daily rewards!",
			button = "Let's go!",
		})
	end
end

function TutorialController.start()
	build()
	Net.event("Effect").OnClientEvent:Connect(onEffect)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local pulse = (math.sin(os.clock() * 5) + 1) / 2
		highlight.FillTransparency = 0.45 + pulse * 0.4
		highlight.OutlineTransparency = pulse * 0.5
		if elapsed >= 0.25 then
			elapsed = 0
			update()
		end
	end)
	StateController.changed:connect(update)
end

return TutorialController
