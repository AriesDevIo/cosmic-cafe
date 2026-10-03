--!strict
local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local DataTemplate = Loader.shared("Config/DataTemplate")
local Economy = Loader.shared("Config/Economy")
local Staff = Loader.shared("Config/Staff")
local Worlds = Loader.shared("Config/Worlds")
local Progression = Loader.shared("Util/Progression")
local Stats = Loader.shared("Util/Stats")

local Buildables = Loader.shared("Config/Buildables")

local ctx = Stats.defaultContext
local streetDefs = Buildables.forWorld("StreetStall")

local function defOf(defs: { any }, id: string): any
	for _, def in defs do
		if def.id == id then
			return def
		end
	end
	error("no build " .. id)
end

-- A profile with the free Coffee Cart built (and lots of money).
local function rich(money: number?)
	local profile = DataTemplate.new()
	profile.money = 0
	assert(Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Station1")))
	profile.money = money or 1e30
	return profile
end

describe("new profile", function()
	it("starts on an empty lot with a free first station", function()
		local profile = DataTemplate.new()
		expect(profile.worlds.StreetStall.unlocked).toBe(true)
		expect(profile.worlds.CloudCity.unlocked).toBe(false)
		expect(Stats.dishLevel(profile, "Coffee")).toBe(0)
		expect(Stats.worldRate(profile, ctx, "StreetStall")).toBe(0)
		expect(profile.tutorial.step).toBe(1)
		local first = Progression.availableBuilds(profile, "StreetStall", streetDefs, 3)
		expect(#first).toBe(1)
		expect(first[1].cost).toBe(0)
		expect(first[1].dish).toBe("Coffee")
	end)
end)

describe("builds", function()
	it("buys a station, unlocking its dish", function()
		local profile = rich(100)
		expect(Stats.dishLevel(profile, "Coffee")).toBe(1)
		expect(Stats.worldRate(profile, ctx, "StreetStall")).toBeGreaterThan(0)
		local donut = defOf(streetDefs, "Station2")
		expect(Progression.buyBuild(profile, "StreetStall", donut)).toBe(true)
		expect(profile.money).toBe(100 - donut.cost)
		expect(Stats.dishLevel(profile, "Donut")).toBe(1)
		expect(profile.builds.StreetStall.Station2).toBe("Station")
	end)

	it("enforces requirements, money and duplicates", function()
		local profile = rich(10)
		expect((Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Counter")))).toBe(false)
		expect((Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Table1")))).toBe(false) -- $15
		profile.money = 1000
		expect(Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Table1"))).toBe(true)
		expect((Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Table1")))).toBe(false)
		expect((Progression.buyBuild(profile, "CloudCity", Buildables.forWorld("CloudCity")[1]))).toBe(false)
	end)

	it("lists at most N available builds, cheapest first", function()
		local profile = rich()
		local list = Progression.availableBuilds(profile, "StreetStall", streetDefs, 3)
		expect(#list).toBe(2) -- Table1 ($15) and Station2 (Donut)
		expect(list[1].id).toBe("Table1")
		for _, def in streetDefs do
			Progression.buyBuild(profile, "StreetStall", def)
		end
		expect(#Progression.availableBuilds(profile, "StreetStall", streetDefs, 3)).toBe(0)
	end)

	it("seats customers once a table is built", function()
		local profile = rich()
		local before = Stats.averageTip(profile, "StreetStall")
		Progression.buyBuild(profile, "StreetStall", defOf(streetDefs, "Table1"))
		expect(Stats.averageTip(profile, "StreetStall")).toBeCloseTo(before * Economy.cafe.seatedTipMultiplier)
	end)

	it("reconciles stations for dishes that already have levels", function()
		local profile = DataTemplate.new()
		profile.worlds.StreetStall.dishes.Donut = 5
		expect(Progression.reconcileBuilds(profile, "StreetStall", streetDefs)).toBe(true)
		expect(Progression.ownsBuild(profile, "StreetStall", "Station2")).toBe(true)
		expect(Progression.ownsBuild(profile, "StreetStall", "Station1")).toBe(true) -- requirement
		expect(Progression.reconcileBuilds(profile, "StreetStall", streetDefs)).toBe(false)
	end)

	it("generates a lot for every world with a free first station", function()
		for _, world in Worlds.list do
			local defs = Buildables.forWorld(world.id)
			local stations = 0
			for _, def in defs do
				if def.kind == "Station" then
					stations += 1
					expect(def.dish ~= nil).toBeTruthy()
				end
			end
			expect(stations).toBe(#world.dishes)
			expect(defs[1].cost).toBe(0)
		end
	end)

	it("parses Requires attributes", function()
		expect(Buildables.parseRequires("A, B,C")).toEqual({ "A", "B", "C" })
		expect(Buildables.parseRequires("")).toEqual({})
		expect(Buildables.parseRequires(nil)).toEqual({})
	end)
end)

describe("buying dishes", function()
	it("charges the formula cost", function()
		local profile = rich(1000)
		local cost = Stats.upgradeCost(profile, "Coffee", 5)
		local ok, _, bought, paid = Progression.buyDish(profile, "Coffee", 5)
		expect(ok).toBe(true)
		expect(bought).toBe(5)
		expect(paid).toBeCloseTo(cost)
		expect(profile.money).toBeCloseTo(1000 - cost)
		expect(Stats.dishLevel(profile, "Coffee")).toBe(6)
	end)

	it("needs the station built unless the plot allows unlocking", function()
		local profile = rich(1e6)
		expect((Progression.buyDish(profile, "Donut", 1))).toBe(false)
		expect(Progression.buyDish(profile, "Donut", 1, true)).toBe(true)
	end)

	it("buys max with amount 0", function()
		local profile = rich(500)
		local ok, _, bought = Progression.buyDish(profile, "Coffee", 0)
		expect(ok).toBe(true)
		expect(bought).toBe(
			Loader.shared("Util/Formula")
				.maxAffordable(Loader.shared("Config/Dishes").byId.Coffee.baseCost, 1.07, 1, 500)
		)
		expect(Stats.upgradeCost(profile, "Coffee", 1)).toBeGreaterThan(profile.money)
	end)

	it("rejects bad input", function()
		local profile = rich(10)
		expect((Progression.buyDish(profile, "Nope", 1))).toBe(false)
		expect((Progression.buyDish(profile, "Coffee", -1))).toBe(false)
		expect((Progression.buyDish(profile, "Coffee", 1.5))).toBe(false)
		expect((Progression.buyDish(profile, "Coffee", 0 / 0))).toBe(false)
		expect((Progression.buyDish(profile, "Coffee", 1e9))).toBe(false)
		expect((Progression.buyDish(profile, "HotCocoa", 1))).toBe(false) -- world locked
		expect((Progression.buyDish(profile, "Burger", 1))).toBe(false) -- too expensive
		expect(profile.money).toBe(10)
	end)
end)

describe("worlds", function()
	it("unlocks in order with an empty lot", function()
		local profile = rich()
		expect((Progression.unlockWorld(profile, "Underwater"))).toBe(false) -- stub
		expect(Progression.unlockWorld(profile, "CloudCity")).toBe(true)
		expect(Stats.dishLevel(profile, "HotCocoa")).toBe(0)
		expect((Progression.unlockWorld(profile, "CloudCity"))).toBe(false)
		expect(Progression.travel(profile, "CloudCity")).toBe(true)
		expect(profile.currentWorld).toBe("CloudCity")
	end)

	it("needs the money", function()
		local profile = rich(Worlds.byId.CloudCity.unlockCost - 1)
		expect((Progression.unlockWorld(profile, "CloudCity"))).toBe(false)
		expect((Progression.travel(profile, "CloudCity"))).toBe(false)
	end)
end)

describe("staff", function()
	it("hires into an empty slot and automates the world", function()
		local profile = rich()
		expect(Stats.isAutomated(profile, "StreetStall", ctx)).toBe(false)
		expect(Progression.hire(profile, "StreetStall", "Barista")).toBe(true)
		expect((Progression.hire(profile, "StreetStall", "Barista"))).toBe(false)
		expect(Progression.hire(profile, "StreetStall", "Waiter")).toBe(true)
		expect(Stats.isAutomated(profile, "StreetStall", ctx)).toBe(true)
	end)

	it("gates the Regional Director behind world 2", function()
		local profile = rich()
		expect((Progression.hire(profile, "StreetStall", "Director"))).toBe(false)
		Progression.unlockWorld(profile, "CloudCity")
		expect(Progression.hire(profile, "StreetStall", "Director")).toBe(true)
	end)

	it("fuses three matching staff into the next rarity and keeps the slot", function()
		local profile = rich()
		local _, _, hired = Progression.hire(profile, "StreetStall", "Barista")
		local a = Progression.addStaff(profile, "Barista", "Common")
		local b = Progression.addStaff(profile, "Barista", "Common")
		local ok, _, fused = Progression.fuse(profile, { hired.id, a.id, b.id })
		expect(ok).toBe(true)
		expect(fused.rarity).toBe("Rare")
		expect(fused.assigned).toBe("StreetStall")
		expect(Stats.cookSpeed(profile, "StreetStall")).toBe(Staff.rarities.Rare.multiplier)
		expect(profile.staff.items[a.id]).toBeNil()
	end)

	it("refuses mismatched or duplicate fuses", function()
		local profile = rich()
		local a = Progression.addStaff(profile, "Barista", "Common")
		local b = Progression.addStaff(profile, "Waiter", "Common")
		local c = Progression.addStaff(profile, "Barista", "Common")
		expect((Progression.fuse(profile, { a.id, b.id, c.id }))).toBe(false)
		expect((Progression.fuse(profile, { a.id, a.id, c.id }))).toBe(false)
		expect((Progression.fuse(profile, { a.id, c.id }))).toBe(false)
		local cosmic = {}
		for i = 1, 3 do
			cosmic[i] = Progression.addStaff(profile, "Barista", "Cosmic").id
		end
		expect((Progression.fuse(profile, cosmic))).toBe(false)
	end)

	it("opens crates with injected rolls", function()
		local profile = rich()
		local ok, _, item = Progression.openCrate(profile, "Basic", 0, 0)
		expect(ok).toBe(true)
		expect(item.rarity).toBe("Common")
		expect(item.assigned).toBeNil()
		local _, _, other = Progression.openCrate(profile, "Stellar", 0.999, 0.999)
		expect(Staff.crates.Stellar.odds[other.rarity] ~= nil).toBeTruthy()
	end)

	it("swaps the previous worker to the bench on assign", function()
		local profile = rich()
		local _, _, first = Progression.hire(profile, "StreetStall", "Waiter")
		local second = Progression.addStaff(profile, "Waiter", "Epic")
		expect(Progression.assignStaff(profile, second.id, "StreetStall")).toBe(true)
		expect(first.assigned).toBeNil()
		expect(Stats.assignedStaff(profile, "StreetStall", "Waiter")).toBe(second)
		expect((Progression.assignStaff(profile, second.id, "CloudCity"))).toBe(false)
	end)
end)

describe("background and offline", function()
	it("needs automation and a Manager to earn in the background", function()
		local profile = rich()
		Progression.unlockWorld(profile, "CloudCity")
		Progression.buyBuild(profile, "CloudCity", Buildables.forWorld("CloudCity")[1])
		Progression.hire(profile, "StreetStall", "Barista")
		Progression.hire(profile, "StreetStall", "Waiter")
		Progression.travel(profile, "CloudCity")
		expect(Stats.backgroundRate(profile, ctx, "StreetStall")).toBe(0)
		Progression.hire(profile, "StreetStall", "Manager")
		local full = Stats.worldRate(profile, ctx, "StreetStall")
		expect(Stats.backgroundRate(profile, ctx, "StreetStall")).toBeCloseTo(full * Economy.cafe.managerBaseEfficiency)
	end)

	it("counts only the current world offline unless a Director is hired", function()
		local profile = rich()
		Progression.unlockWorld(profile, "CloudCity")
		Progression.buyBuild(profile, "CloudCity", Buildables.forWorld("CloudCity")[1])
		for _, world in { "StreetStall", "CloudCity" } do
			Progression.hire(profile, world, "Barista")
			Progression.hire(profile, world, "Waiter")
		end
		local one = Stats.offlineRate(profile, ctx)
		expect(one).toBeCloseTo(Stats.worldRate(profile, ctx, "StreetStall"))
		Progression.hire(profile, "StreetStall", "Director")
		local both = Stats.worldRate(profile, ctx, "StreetStall") + Stats.worldRate(profile, ctx, "CloudCity")
		expect(Stats.offlineRate(profile, ctx)).toBeCloseTo(both)
	end)

	it("has a 2h cap that upgrades to 12h", function()
		local profile = rich()
		expect(Stats.offlineCapSeconds(profile, ctx)).toBe(2 * 3600)
		profile.franchiseNodes = { LongNap1 = true, LongNap2 = true, LongNap3 = true }
		expect(Stats.offlineCapSeconds(profile, ctx)).toBe(12 * 3600)
		local withPass = { doubleMoney = false, autoServePass = false, offlinePass = true }
		expect(Stats.offlineCapSeconds(profile, withPass)).toBe(12 * 3600)
	end)
end)

describe("weather", function()
	it("boosts tagged dishes during a rush", function()
		expect(Stats.weatherMultiplier("HotCocoa", "Rain")).toBe(3)
		expect(Stats.weatherMultiplier("HotCocoa", "Sun")).toBe(1)
		expect(Stats.weatherMultiplier("BerrySmoothie", "Sun")).toBe(3)
		expect(Stats.weatherMultiplier("Coffee", "Rain")).toBe(1)
		expect(Stats.expectedWeatherMultiplier("HotCocoa")).toBeGreaterThan(1)
		expect(Stats.expectedWeatherMultiplier("Coffee")).toBe(1)
	end)
end)

describe("recipes", function()
	it("discovers recipes and applies their bonus", function()
		local profile = rich()
		local before = Stats.dishValue(profile, ctx, "Coffee")
		local ok, _, recipe, isNew = Progression.combine(profile, ctx, { "Milk", "Bean" })
		expect(ok).toBe(true)
		expect(recipe.id).toBe("Latte")
		expect(isNew).toBe(true)
		expect(Stats.dishValue(profile, ctx, "Coffee")).toBeCloseTo(before * 1.5)
		local _, _, _, again = Progression.combine(profile, ctx, { "Bean", "Milk" })
		expect(again).toBe(false)
	end)

	it("charges for misses and rejects locked or duplicate ingredients", function()
		local profile = rich(1000)
		local ok, _, recipe = Progression.combine(profile, ctx, { "Egg", "Sugar" })
		expect(ok).toBe(true)
		expect(recipe).toBeNil()
		expect(profile.money).toBeLessThan(1000)
		expect((Progression.combine(profile, ctx, { "Berry", "Ice" }))).toBe(false)
		expect((Progression.combine(profile, ctx, { "Egg", "Egg" }))).toBe(false)
		expect((Progression.combine(profile, ctx, { "Egg" }))).toBe(false)
	end)
end)

describe("franchise", function()
	it("needs enough lifetime earnings", function()
		local profile = DataTemplate.new()
		expect((Progression.franchise(profile))).toBe(false)
	end)

	it("resets the run but keeps codex, staff and Star Chefs", function()
		local profile = rich()
		Progression.earn(profile, Economy.prestige.divisor * 100)
		Progression.unlockWorld(profile, "CloudCity")
		Progression.hire(profile, "StreetStall", "Barista")
		Progression.recordServe(profile, "Blorb")
		profile.codex.recipes.Latte = true
		local ok, _, gain = Progression.franchise(profile)
		expect(ok).toBe(true)
		expect(gain).toBe(10)
		expect(profile.totalStarChefs).toBe(10)
		expect(profile.money).toBe(0)
		expect(profile.worlds.CloudCity.unlocked).toBe(false)
		expect(Stats.dishLevel(profile, "Coffee")).toBe(0)
		expect(next(profile.builds.StreetStall)).toBeNil()
		expect(profile.codex.species.Blorb).toBe(1)
		expect(profile.codex.recipes.Latte).toBe(true)
		expect(Stats.hasAutoCook(profile, "StreetStall")).toBe(true)
		expect(Stats.incomeMultiplier(profile, ctx)).toBeCloseTo(1 + 10 * Economy.prestige.incomeBonusPerStarChef)
	end)

	it("buys tree nodes with requirements", function()
		local profile = DataTemplate.new()
		profile.starChefs = 5
		expect((Progression.buyFranchiseNode(profile, "TipJar"))).toBe(false)
		expect(Progression.buyFranchiseNode(profile, "SeedMoney")).toBe(true)
		expect(Progression.buyFranchiseNode(profile, "TipJar")).toBe(true)
		expect(profile.starChefs).toBe(1)
		expect((Progression.buyFranchiseNode(profile, "TipJar"))).toBe(false)
		expect(Stats.tipMultiplier(profile, "Blorb")).toBeCloseTo(1.25)
	end)

	it("applies start money and head start after a reset", function()
		local profile = rich()
		profile.franchiseNodes = { SeedMoney = true, HeadStart = true }
		Progression.earn(profile, Economy.prestige.divisor)
		Progression.franchise(profile)
		expect(profile.money).toBe(5000)
		expect(Stats.dishLevel(profile, "Coffee")).toBe(10)
	end)
end)

describe("daily", function()
	it("claims once per day and continues streaks", function()
		local profile = DataTemplate.new()
		local day = 86400
		local ok, _, reward, streak = Progression.claimDaily(profile, ctx, 100 * day)
		expect(ok).toBe(true)
		expect(streak).toBe(1)
		expect(reward).toBeGreaterThanOrEqual(Economy.daily.minReward)
		expect((Progression.claimDaily(profile, ctx, 100 * day + 50))).toBe(false)
		local _, _, _, streak2 = Progression.claimDaily(profile, ctx, 101 * day)
		expect(streak2).toBe(2)
		local _, _, _, streak3 = Progression.claimDaily(profile, ctx, 110 * day)
		expect(streak3).toBe(1)
	end)
end)

describe("next unlock bar", function()
	it("walks dish -> world -> milestone", function()
		local profile = DataTemplate.new()
		expect(Stats.nextUnlock(profile).kind).toBe("Dish")
		for _, dishId in Worlds.byId.StreetStall.dishes do
			profile.worlds.StreetStall.dishes[dishId] = math.max(1, profile.worlds.StreetStall.dishes[dishId])
		end
		local nextWorld = Stats.nextUnlock(profile)
		expect(nextWorld.kind).toBe("World")
		expect(nextWorld.id).toBe("CloudCity")
		profile.worlds.CloudCity.unlocked = true
		expect(Stats.nextUnlock(profile).kind).toBe("Milestone")
	end)
end)

describe("auto-buy", function()
	it("picks an affordable upgrade with the best payback", function()
		local profile = rich(100)
		local dishId, cost = Progression.bestUpgrade(profile, ctx, "StreetStall")
		expect(dishId ~= nil).toBeTruthy()
		expect(cost).toBeLessThanOrEqual(100)
		local broke = rich(0)
		expect((Progression.bestUpgrade(broke, ctx, "StreetStall"))).toBeNil()
	end)
end)

describe("save migration", function()
	it("skips the tutorial for players from before the redesign", function()
		local veteran: any = { version = 1, stats = { served = 40 } }
		DataTemplate.migrate(veteran)
		expect(veteran.tutorial.done).toBe(true)
		local fresh: any = { version = 1, stats = { served = 0 } }
		DataTemplate.migrate(fresh)
		expect(fresh.tutorial).toBeNil()
	end)
end)
