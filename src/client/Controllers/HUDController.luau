--!strict
-- Always-visible HUD: money, income/s, the "next unlock" progress bar, the tip
-- streak meter, weather banner and the menu buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Economy = require(Shared.Config.Economy)
local Stats = require(Shared.Util.Stats)
local Tutorial = require(Shared.Util.Tutorial)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Scale = require(script.Parent.Parent.UI.Scale)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local StateController = require(script.Parent.StateController)

local HUDController = {}

type MenuEntry = { id: string, icon: string, label: string }

-- Menu buttons, top to bottom. Controllers register windows with these ids.
HUDController.menu = {
	{ id = "Shop", icon = "🛒", label = "Menu" },
	{ id = "Staff", icon = "🧑‍🍳", label = "Staff" },
	{ id = "Worlds", icon = "🌍", label = "Worlds" },
	{ id = "Codex", icon = "📖", label = "Codex" },
	{ id = "Lab", icon = "🧪", label = "Lab" },
	{ id = "Franchise", icon = "⭐", label = "Franchise" },
	{ id = "Daily", icon = "📅", label = "Daily" },
	{ id = "Store", icon = "💎", label = "Store" },
} :: { MenuEntry }

local player = Players.LocalPlayer
local moneyLabel: TextLabel
local incomeLabel: TextLabel
local unlockLabel: TextLabel
local unlockFill: Frame
local unlockPercent: TextLabel
local streakFrame: Frame
local streakFill: Frame
local streakLabel: TextLabel
local weatherLabel: TextLabel
local hintLabel: TextLabel
local badges: { [string]: TextLabel } = {}
local menuButtons: { [string]: TextButton } = {}
local menuShown: { [string]: boolean } = {}
local pulses: { [string]: true } = {}

-- Red dot on a menu button (e.g. daily reward ready).
function HUDController.setBadge(id: string, visible: boolean)
	local badge = badges[id]
	if badge then
		badge.Visible = visible
	end
end

local function build()
	local screen = Builder.new("ScreenGui", {
		Name = "CosmicCafeHUD",
		ResetOnSpawn = false,
		DisplayOrder = 1,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Scale.attach(screen)

	-- Money panel (top center)
	local top = Builder.new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(380, 132),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local moneyPanel = Builder.new("Frame", {
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.1,
		Parent = top,
	}, { Builder.corner(), Builder.stroke(Theme.colors.accent, 3) })
	moneyLabel = Builder.label({
		Name = "Money",
		Font = Theme.fonts.title,
		TextColor3 = Theme.colors.gold,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 42),
		MaxTextSize = 40,
		Text = "$0",
		Parent = moneyPanel,
	})
	incomeLabel = Builder.label({
		Name = "Income",
		TextColor3 = Theme.colors.textDim,
		Position = UDim2.fromOffset(10, 46),
		Size = UDim2.new(1, -20, 0, 22),
		MaxTextSize = 20,
		Text = "",
		Parent = moneyPanel,
	})

	-- Next unlock bar
	local unlockBar, fill = Builder.bar({
		Name = "NextUnlock",
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = top,
	}, Theme.colors.good)
	unlockFill = fill
	Builder.stroke(Color3.new(0, 0, 0), 2).Parent = unlockBar
	unlockLabel = Builder.label({
		Position = UDim2.fromOffset(12, 3),
		Size = UDim2.new(1, -70, 1, -6),
		Font = Theme.fonts.bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 18,
		ZIndex = 2,
		Parent = unlockBar,
	})
	unlockPercent = Builder.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 3),
		Size = UDim2.new(0, 56, 1, -6),
		Font = Theme.fonts.bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 18,
		ZIndex = 2,
		Parent = unlockBar,
	})

	-- Streak meter (under the unlock bar, only while streaking)
	local streakBar, sFill = Builder.bar({
		Name = "Streak",
		Position = UDim2.fromOffset(60, 114),
		Size = UDim2.new(1, -120, 0, 16),
		Visible = false,
		Parent = top,
	}, Theme.colors.cyan)
	streakFrame = streakBar
	streakFill = sFill
	streakLabel = Builder.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.fonts.bold,
		TextStrokeTransparency = 0.3,
		MaxTextSize = 14,
		ZIndex = 2,
		Parent = streakBar,
	})

	-- First-time hint (until the first serve)
	hintLabel = Builder.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(520, 44),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.colors.accentDark,
		Font = Theme.fonts.bold,
		Text = "👉 Walk to the ☕ station and tap Cook, then tap a customer to Serve!",
		TextWrapped = true,
		Visible = false,
		MaxTextSize = 18,
		Parent = screen,
	})
	Builder.corner().Parent = hintLabel

	-- Weather banner (top right)
	weatherLabel = Builder.label({
		Name = "Weather",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(260, 34),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Color3.fromRGB(50, 100, 180),
		Font = Theme.fonts.bold,
		Visible = false,
		MaxTextSize = 18,
		Parent = screen,
	})
	Builder.corner().Parent = weatherLabel

	-- Menu buttons (left)
	local menu = Builder.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(78, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = screen,
	}, { Builder.list(nil, 6) })
	for index, entry in HUDController.menu do
		local button = Builder.button({
			Name = entry.id,
			LayoutOrder = index,
			Size = UDim2.fromOffset(72, 56),
			BackgroundColor3 = Theme.colors.panel,
			Text = "",
			Parent = menu,
		}, function()
			EffectsController.play("Click")
			Window.toggle(entry.id)
		end)
		Builder.stroke(Theme.colors.accent, 2).Parent = button
		Builder.label({
			Text = entry.icon,
			Size = UDim2.fromScale(1, 0.62),
			MaxTextSize = 30,
			Parent = button,
		})
		Builder.label({
			Text = entry.label,
			Position = UDim2.fromScale(0, 0.62),
			Size = UDim2.fromScale(1, 0.34),
			Font = Theme.fonts.bold,
			MaxTextSize = 13,
			Parent = button,
		})
		local badge = Builder.label({
			Text = "!",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.colors.bad,
			Font = Theme.fonts.bold,
			Visible = false,
			ZIndex = 3,
			MaxTextSize = 14,
			Parent = button,
		})
		Builder.corner(UDim.new(1, 0)).Parent = badge
		badges[entry.id] = badge
		button.Visible = false
		menuButtons[entry.id] = button
		Builder.new("UIStroke", {
			Name = "Pulse",
			Color = Theme.colors.accent,
			Thickness = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = button,
		})
	end
end

-- Menu buttons appear one by one as the tutorial unlocks them.
local function refreshMenus()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	for id, button in menuButtons do
		local visible = Tutorial.menuVisible(profile, id)
		if visible and not menuShown[id] then
			menuShown[id] = true
			button.Visible = true
			local pop = button:FindFirstChildOfClass("UIScale")
			if pop then
				pop.Scale = 0
				TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			EffectsController.play("Unlock")
		elseif not visible then
			menuShown[id] = false
			button.Visible = false
		end
	end
end

-- Pulsing outline on a menu button (tutorial pointing at it).
function HUDController.pulse(id: string, on: boolean)
	if on then
		pulses[id] = true
	else
		pulses[id] = nil
	end
	local button = menuButtons[id]
	local stroke = if button then button:FindFirstChild("Pulse") :: UIStroke? else nil
	if stroke and not on then
		stroke.Thickness = 0
	end
end

-- Total income per second shown under the money (theoretical full-speed rate).
local function incomePerSecond(): number
	local profile = StateController.get()
	if profile == nil then
		return 0
	end
	local ctx = StateController.context()
	return Stats.worldRate(profile, ctx, profile.currentWorld) + Stats.totalBackgroundRate(profile, ctx)
end

local lastUnlockKey = ""

local function refreshUnlock()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local nextUnlock = Stats.nextUnlock(profile)
	local key = nextUnlock.kind .. nextUnlock.id
	if key ~= lastUnlockKey then
		lastUnlockKey = key
		unlockFill.Size = UDim2.fromScale(0, 1)
	end
	unlockLabel.Text = nextUnlock.label .. " · " .. BigNum.money(nextUnlock.cost)
	unlockPercent.Text = math.floor(nextUnlock.progress * 100) .. "%"
	TweenService:Create(unlockFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(nextUnlock.progress, 1) }):Play()
	unlockFill.BackgroundColor3 = if nextUnlock.progress >= 1 then Theme.colors.gold else Theme.colors.good
end

local function refreshMoney(money: number)
	EffectsController.animateNumber("money", money, function(value)
		moneyLabel.Text = BigNum.money(value)
	end)
	refreshUnlock()
end

local function refreshIncome()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local world = Worlds.byId[profile.currentWorld]
	local auto = if Stats.isAutomated(profile, profile.currentWorld, StateController.context())
		then "  ·  🤖 auto"
		else ""
	incomeLabel.Text = world.displayName .. "  ·  " .. BigNum.rate(incomePerSecond()) .. auto
end

local function refreshStreak()
	local cafe = StateController.runtime().cafe
	local remaining = if cafe then cafe.expiresAt - workspace:GetServerTimeNow() else 0
	if cafe == nil or cafe.streak <= 0 or remaining <= 0 then
		streakFrame.Visible = false
		return
	end
	streakFrame.Visible = true
	local maxStreak = (Economy.streak.maxMultiplier - 1) / Economy.streak.perServe
	streakFill.Size = UDim2.fromScale(math.clamp(cafe.streak / maxStreak, 0, 1), 1)
	streakLabel.Text = string.format("🔥 Tip streak x%.2f  (%ds)", cafe.multiplier, math.ceil(remaining))
end

local function refreshWeather()
	local profile = StateController.get()
	local weather = StateController.runtime().weather
	local state = if profile and weather then weather[profile.currentWorld] else nil
	local world = if profile then Worlds.byId[profile.currentWorld] else nil
	if state == nil or world == nil or world.weather == nil then
		weatherLabel.Visible = false
		return
	end
	local remaining = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
	weatherLabel.Visible = true
	if state.id then
		for _, w in world.weather.weathers do
			if w.id == state.id then
				weatherLabel.Text =
					string.format("%s %s: %s x%g (%ds)", w.icon, w.displayName, w.tag, w.valueMultiplier, remaining)
			end
		end
	else
		weatherLabel.Text = string.format("⛅ Next rush in %ds", remaining)
	end
end

function HUDController.start()
	build()
	StateController.changed:connect(refreshMenus)
	RunService.RenderStepped:Connect(function()
		local wave = (math.sin(os.clock() * 6) + 1) / 2
		for id in pulses do
			local stroke = menuButtons[id] and menuButtons[id]:FindFirstChild("Pulse") :: UIStroke?
			if stroke then
				stroke.Thickness = 3 + wave * 4
			end
		end
	end)
	StateController.changed:connect(function(profile)
		refreshIncome()
		refreshUnlock()
		hintLabel.Visible = profile.stats.served == 0
	end)
	StateController.moneyChanged:connect(refreshMoney)
	StateController.runtimeChanged:connect(function()
		refreshIncome()
		refreshStreak()
		refreshWeather()
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.25 then
			elapsed = 0
			refreshStreak()
			refreshWeather()
		end
	end)
end

return HUDController
