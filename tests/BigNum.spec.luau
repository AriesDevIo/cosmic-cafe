--!strict
local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local BigNum = Loader.shared("Util/BigNum")

describe("BigNum.format", function()
	it("keeps small numbers whole", function()
		expect(BigNum.format(0)).toBe("0")
		expect(BigNum.format(7)).toBe("7")
		expect(BigNum.format(999)).toBe("999")
		expect(BigNum.format(999.99)).toBe("999")
	end)

	it("keeps one decimal below 10", function()
		expect(BigNum.format(5.55)).toBe("5.5")
		expect(BigNum.format(0.25)).toBe("0.2")
	end)

	it("uses short suffixes", function()
		expect(BigNum.format(1000)).toBe("1K")
		expect(BigNum.format(1234)).toBe("1.23K")
		expect(BigNum.format(12345)).toBe("12.3K")
		expect(BigNum.format(123456)).toBe("123K")
		expect(BigNum.format(3.4e6)).toBe("3.4M")
		expect(BigNum.format(1e9)).toBe("1B")
		expect(BigNum.format(2.5e12)).toBe("2.5T")
		expect(BigNum.format(1e15)).toBe("1Qa")
		expect(BigNum.format(1e33)).toBe("1Dc")
		expect(BigNum.format(1e36)).toBe("1UDc")
		expect(BigNum.format(1e63)).toBe("1Vg")
		expect(BigNum.format(1e303)).toBe("1Ce")
	end)

	it("never rounds up past what you have", function()
		expect(BigNum.format(999999)).toBe("999K")
		expect(BigNum.format(1999)).toBe("1.99K")
	end)

	it("handles exact powers of ten across the whole range", function()
		for exponent = 3, 300, 3 do
			local text = BigNum.format(10 ^ exponent)
			expect(string.sub(text, 1, 1)).toBe("1")
			expect(string.find(text, "%.")).toBeNil()
		end
	end)

	it("switches to scientific notation past the suffix list", function()
		expect(BigNum.format(1e306)).toBe("1e306")
		expect(BigNum.format(1.7e308)).toBe("1.7e308")
	end)

	it("formats negatives, infinity and NaN", function()
		expect(BigNum.format(-2500)).toBe("-2.5K")
		expect(BigNum.format(math.huge)).toBe("∞")
		expect(BigNum.format(0 / 0)).toBe("NaN")
	end)

	it("has helpers for money, rates and durations", function()
		expect(BigNum.money(1500)).toBe("$1.5K")
		expect(BigNum.money(-3)).toBe("-$3")
		expect(BigNum.rate(2e6)).toBe("2M/s")
		expect(BigNum.duration(12)).toBe("12s")
		expect(BigNum.duration(249)).toBe("4m 09s")
		expect(BigNum.duration(3900)).toBe("1h 05m")
	end)

	it("has a unique suffix for every group", function()
		local seen = {}
		for _, suffix in BigNum.suffixes do
			expect(seen[suffix]).toBeNil()
			seen[suffix] = true
		end
	end)
end)

describe("BigNum mantissa/exponent", function()
	it("normalizes", function()
		local n = BigNum.new(1500, 0)
		expect(n.m).toBeCloseTo(1.5)
		expect(n.e).toBe(3)
		expect(BigNum.toNumber(n)).toBeCloseTo(1500)
	end)

	it("adds, subtracts, multiplies and divides", function()
		local a, b = BigNum.fromNumber(2e10), BigNum.fromNumber(5e9)
		expect(BigNum.toNumber(BigNum.add(a, b))).toBeCloseTo(2.5e10)
		expect(BigNum.toNumber(BigNum.sub(a, b))).toBeCloseTo(1.5e10)
		expect(BigNum.toNumber(BigNum.mul(a, b))).toBeCloseTo(1e20)
		expect(BigNum.toNumber(BigNum.div(a, b))).toBeCloseTo(4)
	end)

	it("ignores additions far below precision", function()
		local huge = BigNum.new(1, 400)
		local sum = BigNum.add(huge, BigNum.fromNumber(1))
		expect(sum.e).toBe(400)
		expect(sum.m).toBe(1)
	end)

	it("compares", function()
		expect(BigNum.compare(BigNum.new(1, 400), BigNum.new(9, 399))).toBe(1)
		expect(BigNum.compare(BigNum.new(-1, 400), BigNum.new(1, 2))).toBe(-1)
		expect(BigNum.compare(BigNum.new(-1, 400), BigNum.new(-1, 2))).toBe(-1)
		expect(BigNum.compare(BigNum.fromNumber(5), BigNum.fromNumber(5))).toBe(0)
	end)

	it("formats values beyond the double range", function()
		expect(BigNum.formatBig(BigNum.new(1.5, 400))).toBe("1.5e400")
		expect(BigNum.formatBig(BigNum.new(2, 6))).toBe("2M")
		expect(BigNum.formatBig(BigNum.fromNumber(0))).toBe("0")
	end)
end)
