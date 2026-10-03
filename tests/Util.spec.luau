local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local RateLimiter = Loader.shared("Util/RateLimiter")
local TableUtil = Loader.shared("Util/TableUtil")

describe("RateLimiter", function()
	it("allows a burst then throttles", function()
		local limiter = RateLimiter.new(2, 3)
		expect(limiter:check("p", 0)).toBe(true)
		expect(limiter:check("p", 0)).toBe(true)
		expect(limiter:check("p", 0)).toBe(true)
		expect(limiter:check("p", 0)).toBe(false)
	end)

	it("refills over time and tracks keys separately", function()
		local limiter = RateLimiter.new(2, 1)
		expect(limiter:check("a", 0)).toBe(true)
		expect(limiter:check("a", 0.1)).toBe(false)
		expect(limiter:check("b", 0.1)).toBe(true)
		expect(limiter:check("a", 0.6)).toBe(true)
	end)

	it("forgets keys", function()
		local limiter = RateLimiter.new(1, 1)
		limiter:check("a", 0)
		limiter:forget("a")
		expect(limiter:check("a", 0)).toBe(true)
	end)
end)

describe("TableUtil", function()
	it("deep copies", function()
		local original = { a = { b = 1 } }
		local copy = TableUtil.deepCopy(original)
		copy.a.b = 2
		expect(original.a.b).toBe(1)
	end)

	it("reconciles missing and mistyped keys", function()
		local target = { money = 5, nested = { x = "bad" }, extra = true }
		TableUtil.reconcile(target, { money = 0, nested = { x = 1, y = 2 }, list = {} })
		expect(target.money).toBe(5)
		expect(target.nested.x).toBe(1)
		expect(target.nested.y).toBe(2)
		expect(target.extra).toBe(true)
		expect(type(target.list)).toBe("table")
	end)

	it("counts dictionary entries", function()
		expect(TableUtil.count({ a = 1, b = 2 })).toBe(2)
	end)
end)
