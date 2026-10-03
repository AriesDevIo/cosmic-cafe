--!strict
-- Daily window: login streak calendar + claim button, Food Critic status.
-- Pops a "daily reward ready" popup on join when there's something to claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Economy = require(Shared.Config.Economy)
local Formula = require(Shared.Util.Formula)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local PopupController = require(script.Parent.PopupController)
local StateController = require(script.Parent.StateController)

local DailyController = {}

local window: Window.Window
local DAILY = Economy.daily

-- (streak after claiming, can claim now)
local function status(profile: any): (number, boolean)
	local today = Formula.dayIndex(StateController.serverTime())
	return Formula.dailyStreak(profile.daily.lastClaimDay, today, profile.daily.streak, DAILY.streakGraceHours / 24)
end

local function rewardFor(profile: any, streak: number): number
	local seconds =
		Formula.dailyRewardSeconds(streak, DAILY.baseRewardSeconds, DAILY.perStreakDaySeconds, DAILY.maxStreakDays)
	local rate = Stats.worldRate(profile, StateController.context(), profile.currentWorld)
	return math.max(DAILY.minReward, rate * seconds)
end

local function claim()
	EffectsController.play("Buy")
	Net.event("ClaimDaily"):FireServer()
end

local function render()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(window)
	local nextStreak, canClaim = status(profile)
	local shownStreak = if canClaim then nextStreak else profile.daily.streak

	Builder.label({
		LayoutOrder = 1,
		Text = string.format("🔥 Login streak: %d day%s", shownStreak, if shownStreak == 1 then "" else "s"),
		Font = Theme.fonts.title,
		Size = UDim2.new(1, 0, 0, 34),
		MaxTextSize = 26,
		Parent = window.body,
	})
	local days = Builder.new("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 86),
		BackgroundTransparency = 1,
		Parent = window.body,
	}, { Builder.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	for day = 1, DAILY.maxStreakDays do
		local reached = day <= shownStreak
		local isToday = canClaim and day == math.min(nextStreak, DAILY.maxStreakDays)
		local card = Builder.new("Frame", {
			LayoutOrder = day,
			Size = UDim2.fromOffset(72, 84),
			BackgroundColor3 = if reached then Theme.colors.goodDark else Theme.colors.panelDark,
			Parent = days,
		}, { Builder.corner(), Builder.stroke(if isToday then Theme.colors.gold else Theme.colors.panelLight, 3) })
		Builder.label({
			Text = "Day " .. day .. (if day == DAILY.maxStreakDays then "+" else ""),
			Font = Theme.fonts.bold,
			Position = UDim2.fromOffset(4, 6),
			Size = UDim2.new(1, -8, 0, 20),
			MaxTextSize = 15,
			Parent = card,
		})
		local seconds =
			Formula.dailyRewardSeconds(day, DAILY.baseRewardSeconds, DAILY.perStreakDaySeconds, DAILY.maxStreakDays)
		Builder.label({
			Text = if reached and not isToday then "✅" else "💰",
			Position = UDim2.fromOffset(4, 28),
			Size = UDim2.new(1, -8, 0, 28),
			Parent = card,
		})
		Builder.label({
			Text = BigNum.duration(seconds),
			TextColor3 = Theme.colors.textDim,
			Position = UDim2.fromOffset(4, 60),
			Size = UDim2.new(1, -8, 0, 16),
			MaxTextSize = 12,
			Parent = card,
		})
	end

	Builder.button({
		LayoutOrder = 3,
		Text = if canClaim then "Claim " .. BigNum.money(rewardFor(profile, nextStreak)) else "Come back tomorrow!",
		Size = UDim2.fromOffset(300, 52),
		BackgroundColor3 = if canClaim then Theme.colors.good else Theme.colors.locked,
		MaxTextSize = 22,
		Parent = window.body,
	}, function()
		if canClaim then
			claim()
		end
	end)
	Builder.label({
		LayoutOrder = 4,
		Text = "Rewards are worth minutes of your current income. Miss more than "
			.. DAILY.streakGraceHours
			.. "h and the streak resets.",
		TextColor3 = Theme.colors.textDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 36),
		MaxTextSize = 15,
		Parent = window.body,
	})

	local today = Formula.dayIndex(StateController.serverTime())
	local criticDone = profile.daily.criticDay >= today
	local critic = Builder.new("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundColor3 = Theme.colors.panelLight,
		Parent = window.body,
	}, { Builder.corner() })
	Builder.label({
		Text = "🧐 Daily Food Critic",
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 28),
		MaxTextSize = 22,
		Parent = critic,
	})
	Builder.label({
		Text = if criticDone
			then "✅ Served today! A new critic visits tomorrow."
			else string.format(
				"A critic will visit your cafe soon. Serve them for %s of income!",
				BigNum.duration(DAILY.criticRewardSeconds)
			),
		TextColor3 = if criticDone then Theme.colors.good else Theme.colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -24, 0, 22),
		MaxTextSize = 15,
		Parent = critic,
	})
end

local announced = false

local function onState()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local nextStreak, canClaim = status(profile)
	HUDController.setBadge("Daily", canClaim)
	if canClaim and not announced then
		announced = true
		PopupController.show({
			title = "📅 Daily reward!",
			highlight = "+" .. BigNum.money(rewardFor(profile, nextStreak)),
			body = string.format("Day %d of your login streak. Come back every day for bigger rewards!", nextStreak),
			button = "Claim",
			onClose = claim,
		})
	end
	Window.refresh("Daily")
end

function DailyController.start()
	window = Window.create("Daily", "📅 Daily")
	window.render = render
	StateController.changed:connect(onState)
end

return DailyController
