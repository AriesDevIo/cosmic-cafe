--!strict
local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Formula = Loader.shared("Util/Formula")

local milestones = {
	{ level = 25, speedMultiplier = 2 },
	{ level = 50, speedMultiplier = 2 },
	{ level = 100, speedMultiplier = 2 },
	{ level = 200, speedMultiplier = 2 },
}

describe("Formula.cost", function()
	it("matches the level-by-level sum", function()
		local base, growth, owned = 4, 1.07, 13
		local manual = 0
		for i = owned, owned + 9 do
			manual += base * growth ^ i
		end
		expect(Formula.cost(base, growth, owned, 10)).toBeCloseTo(manual)
	end)

	it("is linear when growth is 1 and zero for no levels", function()
		expect(Formula.cost(5, 1, 3, 4)).toBe(20)
		expect(Formula.cost(5, 1.07, 3, 0)).toBe(0)
	end)
end)

describe("Formula.maxAffordable", function()
	it("buys exactly what money allows", function()
		local base, growth, owned = 4, 1.07, 7
		for _, money in { 0, 3, 10, 100, 12345, 9.9e9 } do
			local n = Formula.maxAffordable(base, growth, owned, money)
			expect(Formula.cost(base, growth, owned, n)).toBeLessThanOrEqual(money * (1 + 1e-12))
			expect(Formula.cost(base, growth, owned, n + 1)).toBeGreaterThan(money)
		end
	end)

	it("handles the exact boundary", function()
		local cost = Formula.cost(10, 1.15, 0, 5)
		expect(Formula.maxAffordable(10, 1.15, 0, cost)).toBe(5)
	end)
end)

describe("milestones", function()
	it("doubles speed at each milestone", function()
		expect(Formula.milestoneSpeed(24, milestones)).toBe(1)
		expect(Formula.milestoneSpeed(25, milestones)).toBe(2)
		expect(Formula.milestoneSpeed(99, milestones)).toBe(4)
		expect(Formula.milestoneSpeed(250, milestones)).toBe(16)
	end)

	it("finds the next milestone", function()
		expect(Formula.nextMilestone(0, milestones).level).toBe(25)
		expect(Formula.nextMilestone(25, milestones).level).toBe(50)
		expect(Formula.nextMilestone(200, milestones)).toBeNil()
	end)

	it("speeds up cooking and income", function()
		expect(Formula.cookTime(2, 25, milestones, 1)).toBe(1)
		expect(Formula.cookTime(2, 25, milestones, 2)).toBe(0.5)
		expect(Formula.dishRate(1, 2, 24, milestones, 1)).toBeCloseTo(12)
		expect(Formula.dishRate(1, 2, 25, milestones, 1)).toBeCloseTo(25)
		expect(Formula.dishRate(1, 2, 0, milestones, 1)).toBe(0)
	end)
end)

describe("dish value", function()
	it("is linear without level growth", function()
		expect(Formula.dishValue(3, 10)).toBe(30)
		expect(Formula.dishValue(3, 0)).toBe(0)
	end)

	it("compounds with level growth", function()
		expect(Formula.dishValue(1, 3, 1.1)).toBeCloseTo(3 * 1.21)
	end)
end)

describe("streak", function()
	it("grows per serve and caps", function()
		expect(Formula.streakMultiplier(0, 0.05, 2.5)).toBe(1)
		expect(Formula.streakMultiplier(10, 0.05, 2.5)).toBeCloseTo(1.5)
		expect(Formula.streakMultiplier(1000, 0.05, 2.5)).toBe(2.5)
		expect(Formula.streakMultiplier(-3, 0.05, 2.5)).toBe(1)
	end)
end)

describe("Star Chefs", function()
	it("uses a square-root curve", function()
		expect(Formula.starChefsTotal(0, 1e6, 0.5)).toBe(0)
		expect(Formula.starChefsTotal(1e6, 1e6, 0.5)).toBe(1)
		expect(Formula.starChefsTotal(4e6, 1e6, 0.5)).toBe(2)
		expect(Formula.starChefsTotal(1e8, 1e6, 0.5)).toBe(10)
	end)

	it("only awards new Star Chefs", function()
		expect(Formula.starChefsGain(1e8, 4, 1e6, 0.5)).toBe(6)
		expect(Formula.starChefsGain(1e6, 4, 1e6, 0.5)).toBe(0)
	end)

	it("inverts to the earnings needed", function()
		expect(Formula.earningsForStarChefs(10, 1e6, 0.5)).toBeCloseTo(1e8)
		expect(Formula.starChefsTotal(Formula.earningsForStarChefs(7, 1e6, 0.5), 1e6, 0.5)).toBe(7)
	end)

	it("adds a flat bonus per Star Chef", function()
		expect(Formula.starChefMultiplier(15, 0.1)).toBeCloseTo(2.5)
	end)
end)

describe("offline earnings", function()
	it("caps the time and applies efficiency", function()
		local earned, counted = Formula.offlineEarnings(10, 3 * 3600, 2 * 3600, 0.5)
		expect(counted).toBe(7200)
		expect(earned).toBe(36000)
	end)

	it("pays nothing for no time or no income", function()
		expect((Formula.offlineEarnings(10, 0, 7200, 0.5))).toBe(0)
		expect((Formula.offlineEarnings(0, 500, 7200, 0.5))).toBe(0)
	end)
end)

describe("weightedPick", function()
	local weights = { A = 1, B = 3, C = 0 }

	it("is deterministic for a roll", function()
		expect(Formula.weightedPick(weights, 0)).toBe("A")
		expect(Formula.weightedPick(weights, 0.24)).toBe("A")
		expect(Formula.weightedPick(weights, 0.26)).toBe("B")
		expect(Formula.weightedPick(weights, 0.9999)).toBe("B")
		expect(Formula.weightedPick(weights, 1)).toBe("B")
	end)

	it("never picks zero weights and handles empty tables", function()
		for i = 0, 99 do
			expect(Formula.weightedPick(weights, i / 100) ~= "C").toBeTruthy()
		end
		expect(Formula.weightedPick({}, 0.5)).toBeNil()
	end)
end)

describe("daily streak", function()
	it("continues on consecutive days", function()
		local streak, canClaim = Formula.dailyStreak(100, 101, 3, 2)
		expect(streak).toBe(4)
		expect(canClaim).toBe(true)
	end)

	it("refuses a second claim the same day", function()
		local streak, canClaim = Formula.dailyStreak(101, 101, 4, 2)
		expect(streak).toBe(4)
		expect(canClaim).toBe(false)
	end)

	it("resets after the grace period and on the first claim", function()
		expect((Formula.dailyStreak(100, 105, 9, 2))).toBe(1)
		expect((Formula.dailyStreak(0, 105, 0, 2))).toBe(1)
	end)

	it("rewards more for longer streaks up to a cap", function()
		expect(Formula.dailyRewardSeconds(1, 120, 60, 7)).toBe(120)
		expect(Formula.dailyRewardSeconds(3, 120, 60, 7)).toBe(240)
		expect(Formula.dailyRewardSeconds(30, 120, 60, 7)).toBe(480)
	end)

	it("computes the day index", function()
		expect(Formula.dayIndex(86400 * 3 + 5)).toBe(3)
	end)
end)

describe("misc", function()
	it("finds the next rarity", function()
		local order = { "Common", "Rare", "Epic" }
		expect(Formula.nextRarity(order, "Common")).toBe("Rare")
		expect(Formula.nextRarity(order, "Epic")).toBeNil()
		expect(Formula.nextRarity(order, "Bogus")).toBeNil()
	end)

	it("builds order independent recipe keys", function()
		expect(Formula.recipeKey({ "Milk", "Bean" })).toBe("Bean+Milk")
		expect(Formula.recipeKey({ "Bean", "Milk" })).toBe(Formula.recipeKey({ "Milk", "Bean" }))
	end)

	it("clamps progress", function()
		expect(Formula.progress(5, 10)).toBe(0.5)
		expect(Formula.progress(50, 10)).toBe(1)
		expect(Formula.progress(5, 0)).toBe(1)
	end)
end)
