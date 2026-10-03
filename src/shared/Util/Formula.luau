--!strict
-- Pure economy math. No config lookups and no Roblox APIs, so everything here
-- is unit tested with Lune (tests/Formula.spec.luau).

local Formula = {}

export type Milestone = {
	level: number,
	speedMultiplier: number,
}

-- Cost of buying `amount` levels when `owned` levels are already owned:
-- sum_{i=owned}^{owned+amount-1} base * growth^i
function Formula.cost(base: number, growth: number, owned: number, amount: number): number
	if amount <= 0 then
		return 0
	end
	if growth == 1 then
		return base * amount
	end
	return base * growth ^ owned * (growth ^ amount - 1) / (growth - 1)
end

-- Largest number of levels affordable with `money` (0 if not even one).
function Formula.maxAffordable(base: number, growth: number, owned: number, money: number): number
	if money <= 0 or base <= 0 then
		return 0
	end
	local count: number
	if growth == 1 then
		count = math.floor(money / base)
	else
		local first = base * growth ^ owned
		count = math.floor(math.log(money * (growth - 1) / first + 1) / math.log(growth))
	end
	count = math.max(count, 0)
	-- guard against floating point at the boundary
	while count > 0 and Formula.cost(base, growth, owned, count) > money * (1 + 1e-12) do
		count -= 1
	end
	return count
end

-- Product of every reached milestone's speed multiplier.
function Formula.milestoneSpeed(level: number, milestones: { Milestone }): number
	local speed = 1
	for _, milestone in milestones do
		if level >= milestone.level then
			speed *= milestone.speedMultiplier
		end
	end
	return speed
end

-- The next milestone level above `level`, or nil when all are reached.
function Formula.nextMilestone(level: number, milestones: { Milestone }): Milestone?
	local best: Milestone? = nil
	for _, milestone in milestones do
		if milestone.level > level and (best == nil or milestone.level < best.level) then
			best = milestone
		end
	end
	return best
end

-- Value of one serving.
function Formula.dishValue(baseIncome: number, level: number, levelGrowth: number?): number
	if level <= 0 then
		return 0
	end
	local growth = levelGrowth or 1
	return baseIncome * level * growth ^ (level - 1)
end

-- Seconds to cook one serving.
function Formula.cookTime(baseCookTime: number, level: number, milestones: { Milestone }, speed: number): number
	return baseCookTime / (Formula.milestoneSpeed(level, milestones) * math.max(speed, 1e-6))
end

-- Income per second of a dish that is cooked and served without pause.
function Formula.dishRate(
	baseIncome: number,
	baseCookTime: number,
	level: number,
	milestones: { Milestone },
	speed: number
): number
	if level <= 0 then
		return 0
	end
	return Formula.dishValue(baseIncome, level) / Formula.cookTime(baseCookTime, level, milestones, speed)
end

-- Tip streak multiplier: 1 + streak * perServe, capped.
function Formula.streakMultiplier(streak: number, perServe: number, maxMultiplier: number): number
	return math.min(1 + math.max(streak, 0) * perServe, maxMultiplier)
end

-- Total Star Chefs a player is worth after earning `lifetimeEarnings` overall.
function Formula.starChefsTotal(lifetimeEarnings: number, divisor: number, exponent: number): number
	if lifetimeEarnings <= 0 then
		return 0
	end
	return math.floor((lifetimeEarnings / divisor) ^ exponent + 1e-9)
end

-- Star Chefs a Franchise would award right now.
function Formula.starChefsGain(
	lifetimeEarnings: number,
	alreadyEarned: number,
	divisor: number,
	exponent: number
): number
	return math.max(0, Formula.starChefsTotal(lifetimeEarnings, divisor, exponent) - alreadyEarned)
end

-- Lifetime earnings needed to be worth `total` Star Chefs.
function Formula.earningsForStarChefs(total: number, divisor: number, exponent: number): number
	return divisor * total ^ (1 / exponent)
end

function Formula.starChefMultiplier(totalStarChefs: number, bonusPerStarChef: number): number
	return 1 + totalStarChefs * bonusPerStarChef
end

-- Offline payout: (earned, secondsCounted).
function Formula.offlineEarnings(
	ratePerSecond: number,
	secondsAway: number,
	capSeconds: number,
	efficiency: number
): (number, number)
	if secondsAway <= 0 or ratePerSecond <= 0 then
		return 0, 0
	end
	local counted = math.min(secondsAway, capSeconds)
	return ratePerSecond * counted * efficiency, counted
end

function Formula.progress(current: number, target: number): number
	if target <= 0 then
		return 1
	end
	return math.clamp(current / target, 0, 1)
end

-- Picks a key from a weight table using roll in [0, 1). Keys are visited in
-- sorted order so the result is deterministic for a given roll.
function Formula.weightedPick(weights: { [string]: number }, roll: number): string?
	local keys: { string } = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys)
	local target = math.clamp(roll, 0, 0.999999999) * total
	local acc = 0
	for _, key in keys do
		acc += weights[key]
		if target < acc then
			return key
		end
	end
	return keys[#keys]
end

-- Daily login --------------------------------------------------------------

function Formula.dayIndex(unixSeconds: number): number
	return unixSeconds // 86400
end

-- Returns (newStreak, canClaim). A claim on the next day continues the
-- streak, a gap longer than graceDays resets it to 1.
function Formula.dailyStreak(lastClaimDay: number, today: number, streak: number, graceDays: number): (number, boolean)
	if lastClaimDay >= today then
		return streak, false
	end
	if lastClaimDay <= 0 or today - lastClaimDay > graceDays then
		return 1, true
	end
	return streak + 1, true
end

function Formula.dailyRewardSeconds(streak: number, baseSeconds: number, perDay: number, maxDays: number): number
	return baseSeconds + perDay * (math.clamp(streak, 1, maxDays) - 1)
end

-- Staff -----------------------------------------------------------------------

-- Next rarity in `order` after `rarity`, nil if it's the last.
function Formula.nextRarity(order: { string }, rarity: string): string?
	local index = table.find(order, rarity)
	if index == nil then
		return nil
	end
	return order[index + 1]
end

-- Recipes -------------------------------------------------------------------

-- Canonical key for an ingredient combination (order independent).
function Formula.recipeKey(ingredients: { string }): string
	local sorted = table.clone(ingredients)
	table.sort(sorted)
	return table.concat(sorted, "+")
end

return Formula
