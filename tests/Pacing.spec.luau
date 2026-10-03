-- Guards the pacing targets from the design doc. If you retune on purpose,
-- run `lune run scripts/simulate` and adjust these bounds together.
local TestKit = require("./lib/TestKit")
local PacingSim = require("../scripts/lib/PacingSim")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local result = PacingSim.run({ seconds = 2.75 * 3600 })

describe("pacing", function()
	it("makes the first sale within 30 seconds", function()
		expect(result.firstSale).toBeLessThan(30)
	end)

	it("hits a new goal every ~20-40s in the first 5 minutes", function()
		local gaps = PacingSim.goalGaps(result, 0, 300)
		local sum, longest = 0, 0
		for _, gap in gaps do
			sum += gap
			longest = math.max(longest, gap)
		end
		expect(sum / #gaps).toBeGreaterThanOrEqual(15)
		expect(sum / #gaps).toBeLessThanOrEqual(45)
		expect(longest).toBeLessThanOrEqual(75)
	end)

	it("hires the first staff member around 2 minutes", function()
		expect(result.firstHire).toBeGreaterThanOrEqual(60)
		expect(result.firstHire).toBeLessThanOrEqual(240)
	end)

	it("unlocks World 2 at 30-60 minutes", function()
		local first = result.worldUnlocks.CloudCity[1]
		expect(first).toBeGreaterThanOrEqual(30 * 60)
		expect(first).toBeLessThanOrEqual(60 * 60)
	end)

	it("reaches the first Franchise at 1.5-2 hours", function()
		local franchise = result.franchises[1]
		expect(franchise ~= nil).toBeTruthy()
		expect(franchise.time).toBeGreaterThanOrEqual(90 * 60)
		expect(franchise.time).toBeLessThanOrEqual(120 * 60)
	end)

	it("plays the second run about twice as fast", function()
		local first, second = result.franchises[1], result.franchises[2]
		expect(second ~= nil).toBeTruthy()
		local speedup = first.runTime / second.runTime
		expect(speedup).toBeGreaterThanOrEqual(1.7)
		expect(speedup).toBeLessThanOrEqual(3)
	end)
end)
