--!strict
-- Juice: toasts, server announcements, discovery cards, coin pops, sounds and
-- a smooth number animator other controllers use for money counters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)

local EffectsController = {}

local player = Players.LocalPlayer
local screen: ScreenGui
local toastList: Frame
local announceList: Frame

-- Sounds ----------------------------------------------------------------------------

local soundCache: { [string]: Sound } = {}

function EffectsController.play(name: string)
	local def = Sounds[name]
	if def == nil then
		return
	end
	local sound = soundCache[name]
	if sound == nil then
		sound = Builder.new("Sound", {
			Name = name,
			SoundId = def.id,
			Volume = def.volume,
			PlaybackSpeed = def.pitch,
			Parent = SoundService,
		})
		soundCache[name] = sound
	end
	SoundService:PlayLocalSound(sound)
end

-- Number animation ------------------------------------------------------------------

type Animated = { current: number, target: number, setter: (number) -> () }
local animated: { [string]: Animated } = {}

-- Smoothly animates a displayed number toward `target`; `setter` draws it.
function EffectsController.animateNumber(key: string, target: number, setter: (number) -> ())
	local entry = animated[key]
	if entry == nil then
		animated[key] = { current = target, target = target, setter = setter }
		setter(target)
		return
	end
	entry.target = target
	entry.setter = setter
	-- jumps of more than 1000x (franchise reset, huge payouts) snap instantly
	if target <= 0 or entry.current <= 0 or target / entry.current > 1000 or entry.current / target > 1000 then
		entry.current = target
		setter(target)
	end
end

-- Toasts / announcements -------------------------------------------------------------

local STYLE_COLORS: { [string]: Color3 } = {
	info = Theme.colors.panelLight,
	success = Theme.colors.goodDark,
	error = Theme.colors.bad,
	weather = Color3.fromRGB(60, 120, 200),
}

function EffectsController.toast(text: string, style: string?)
	local color = STYLE_COLORS[style or "info"] or Theme.colors.panelLight
	local toast = Builder.new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		Parent = toastList,
	}, {
		Builder.corner(),
		Builder.stroke(Color3.new(0, 0, 0), 2),
		Builder.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	Builder.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.fonts.bold,
		TextSize = 18,
		TextColor3 = Theme.colors.text,
		Text = text,
		Parent = toast,
	})
	if style == "error" then
		EffectsController.play("Error")
	end
	task.delay(3, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		fade:Play()
		for _, child in toast:GetDescendants() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			elseif child:IsA("UIStroke") then
				TweenService:Create(child, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.45)
		toast:Destroy()
	end)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		toasts[1]:Destroy()
	end
end

function EffectsController.announce(text: string, colorHex: string?)
	local color = Theme.colors.star
	if colorHex then
		local ok, parsed = pcall(Color3.fromHex, colorHex)
		if ok then
			color = parsed
		end
	end
	local banner = Builder.label({
		Size = UDim2.new(1, 0, 0, 30),
		Font = Theme.fonts.title,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		Text = text,
		MaxTextSize = 24,
		Parent = announceList,
	})
	task.delay(6, function()
		TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.7)
		banner:Destroy()
	end)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system then
			(system :: TextChannel):DisplaySystemMessage(text)
		end
	end)
end

-- A centered card for new species / recipes / big moments.
function EffectsController.card(title: string, subtitle: string, color: Color3)
	EffectsController.play("Unlock")
	local card = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromOffset(380, 120),
		BackgroundColor3 = Theme.colors.panel,
		Parent = screen,
	}, {
		Builder.corner(),
		Builder.stroke(color, 4),
		Builder.new("UIScale", { Name = "Scale", Scale = 0.2 }),
	})
	Builder.label({
		Text = title,
		Font = Theme.fonts.title,
		TextColor3 = color,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 50),
		MaxTextSize = 34,
		Parent = card,
	})
	Builder.label({
		Text = subtitle,
		Position = UDim2.fromOffset(12, 66),
		Size = UDim2.new(1, -24, 0, 40),
		TextColor3 = Theme.colors.textDim,
		MaxTextSize = 20,
		Parent = card,
	})
	local scale = card:FindFirstChild("Scale") :: UIScale
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(3, function()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0 }):Play()
		task.wait(0.3)
		card:Destroy()
	end)
end

-- World effects ------------------------------------------------------------------------

-- Floating "+$1.2K" over a world position.
function EffectsController.coinPop(position: Vector3, amount: number, color: Color3?, big: boolean?)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 4, 0)
	anchor.Parent = workspace.Terrain
	local size = if big then 260 else 160
	local gui = Builder.new("BillboardGui", {
		Size = UDim2.fromOffset(size, size / 3),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = anchor,
		Parent = anchor,
	})
	local text = Builder.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.fonts.title,
		TextScaled = true,
		TextColor3 = color or Theme.colors.gold,
		TextStrokeTransparency = 0,
		Text = "+" .. BigNum.money(amount),
		Parent = gui,
	})
	local rise = TweenService:Create(
		gui,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 4, 0) }
	)
	rise:Play()
	TweenService:Create(text, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

local function flash(color: Color3)
	local frame = Builder.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.5,
		ZIndex = 50,
		Parent = screen,
	})
	TweenService:Create(frame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	task.delay(0.85, function()
		frame:Destroy()
	end)
end

local function onEffect(kind: string, data: any)
	if kind == "Coin" then
		local big = data.golden or data.multiplier >= 2
		local color = if data.golden then Theme.colors.gold elseif data.multiplier > 1 then Theme.colors.cyan else nil
		EffectsController.coinPop(data.position, data.amount, color, big)
		EffectsController.play(if big then "BigCoin" else "Coin")
		if data.golden then
			flash(Theme.colors.gold)
		end
	elseif kind == "Cook" then
		EffectsController.play("Cook")
	elseif kind == "Golden" then
		EffectsController.toast("🏆 A GOLDEN ALIEN walked in! Serve it for a huge tip!", "success")
		EffectsController.play("Unlock")
	elseif kind == "RecipeFail" then
		EffectsController.play("Error")
	end
end

local function onDiscovery(kind: string, id: string, firstOnServer: boolean)
	if kind == "Species" then
		local species = Customers.byId[id]
		if species then
			local rarity = Customers.rarities[species.rarity]
			EffectsController.card(
				species.icon .. " " .. species.displayName,
				"New " .. species.rarity .. " alien in your Codex!",
				rarity.color
			)
		end
	elseif kind == "Recipe" then
		local recipe = Dishes.recipeById[id]
		if recipe then
			local subtitle = if firstOnServer then "🏅 First discovery on this server!" else "New recipe discovered!"
			EffectsController.card(recipe.icon .. " " .. recipe.displayName, subtitle, Theme.colors.star)
		end
	end
end

function EffectsController.start()
	screen = Builder.new("ScreenGui", {
		Name = "CosmicCafeEffects",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	})
	toastList = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0.9, 0, 0, 240),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Builder.new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	announceList = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0.8, 0, 0, 100),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { Builder.list(nil, 4) })

	Net.event("Notify").OnClientEvent:Connect(function(text, style)
		EffectsController.toast(text, style)
	end)
	Net.event("Announce").OnClientEvent:Connect(function(text, colorHex)
		EffectsController.announce(text, colorHex)
	end)
	Net.event("Effect").OnClientEvent:Connect(onEffect)
	Net.event("Discovery").OnClientEvent:Connect(onDiscovery)

	RunService.RenderStepped:Connect(function(dt)
		local alpha = 1 - math.exp(-dt * 10)
		for _, entry in animated do
			if entry.current ~= entry.target then
				local nextValue = entry.current + (entry.target - entry.current) * alpha
				if math.abs(entry.target - nextValue) <= math.abs(entry.target) * 1e-4 then
					nextValue = entry.target
				end
				entry.current = nextValue
				entry.setter(nextValue)
			end
		end
	end)
end

return EffectsController
