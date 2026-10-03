--!strict
local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Buildables = Loader.shared("Config/Buildables")
local DataTemplate = Loader.shared("Config/DataTemplate")
local TutorialConfig = Loader.shared("Config/Tutorial")
local Worlds = Loader.shared("Config/Worlds")
local Progression = Loader.shared("Util/Progression")
local Tutorial = Loader.shared("Util/Tutorial")

local facts = Tutorial.defaultFacts
local defs = Buildables.forWorld("StreetStall")

local function build(profile: any, id: string)
	for _, def in defs do
		if def.id == id then
			profile.money += def.cost
			assert(Progression.buyBuild(profile, "StreetStall", def))
			return
		end
	end
	error("no build " .. id)
end

describe("tutorial", function()
	it("walks through every step in order", function()
		local profile = DataTemplate.new()
		expect(Tutorial.current(profile).id).toBe("BuildFirstStation")
		expect((Tutorial.advance(profile, facts))).toBe(false)

		build(profile, "Station1")
		Tutorial.advance(profile, facts)
		expect(Tutorial.current(profile).id).toBe("ServeFirst")

		Progression.countServe(profile)
		Tutorial.advance(profile, facts)
		expect(Tutorial.current(profile).id).toBe("CollectCash")

		profile.stats.cashCollected = 1
		Tutorial.advance(profile, facts)
		expect(Tutorial.current(profile).id).toBe("BuyTable")

		build(profile, "Table1")
		Tutorial.advance(profile, facts)
		expect(Tutorial.current(profile).id).toBe("BuySecondStation")

		build(profile, "Station2")
		Tutorial.advance(profile, facts)
		expect(Tutorial.current(profile).id).toBe("HireBarista")

		profile.money = 1e6
		Progression.hire(profile, "StreetStall", "Barista")
		local changed, finished = Tutorial.advance(profile, facts)
		expect(changed).toBe(true)
		expect(finished).toBe(true)
		expect(profile.tutorial.done).toBe(true)
		expect(Tutorial.current(profile)).toBeNil()
		expect((Tutorial.advance(profile, facts))).toBe(false)
	end)

	it("skips the table step on plots that already have tables", function()
		local profile = DataTemplate.new()
		profile.tutorial.step = 4
		Tutorial.advance(profile, { hasTables = true })
		expect(Tutorial.current(profile).id).toBe("BuySecondStation")
	end)

	it("reveals menu buttons one by one", function()
		local profile = DataTemplate.new()
		expect(Tutorial.menuVisible(profile, "Shop")).toBe(false)
		expect(Tutorial.menuVisible(profile, "Staff")).toBe(false)
		profile.tutorial.step = 3
		expect(Tutorial.menuVisible(profile, "Shop")).toBe(true)
		expect(Tutorial.menuVisible(profile, "Staff")).toBe(false)
		profile.tutorial.step = 6
		expect(Tutorial.menuVisible(profile, "Staff")).toBe(true)
		expect(Tutorial.menuVisible(profile, "Codex")).toBe(false)
		profile.tutorial.done = true
		expect(Tutorial.menuVisible(profile, "Codex")).toBe(true)
		expect(Tutorial.menuVisible(profile, "Worlds")).toBe(false)
		profile.lifetimeEarnings = Worlds.list[2].unlockCost
		expect(Tutorial.menuVisible(profile, "Worlds")).toBe(true)
		expect(Tutorial.menuVisible(profile, "Franchise")).toBe(false)
		profile.franchiseCount = 1
		expect(Tutorial.menuVisible(profile, "Franchise")).toBe(true)
	end)

	it("has a reward and valid menu rules", function()
		expect(TutorialConfig.rewardMoney).toBeGreaterThan(0)
		expect(#TutorialConfig.steps).toBe(6)
	end)
end)
