--!strict
-- Minimal describe/it/expect test framework for Lune.

local TestKit = {}

type Failure = { name: string, message: string }

local stack: { string } = {}
local results = {
	passed = 0,
	failed = 0,
	failures = {} :: { Failure },
}
TestKit.results = results

function TestKit.describe(name: string, body: () -> ())
	table.insert(stack, name)
	body()
	table.remove(stack)
end

function TestKit.it(name: string, body: () -> ())
	local fullName = table.concat(stack, " > ") .. " > " .. name
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName, message = tostring(err) })
	end
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, tolerance: number?) -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeGreaterThanOrEqual: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toBeLessThanOrEqual: (expected: number) -> (),
	toBeNil: () -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
}

function TestKit.expect(actual: any): Expectation
	local function fail(message: string)
		error(message, 3)
	end
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				fail("expected " .. show(expected) .. ", got " .. show(actual))
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				fail("tables are not deeply equal")
			end
		end,
		toBeCloseTo = function(expected: number, tolerance: number?)
			local tol = tolerance or 1e-6
			local scale = math.max(1, math.abs(expected))
			if math.abs(actual - expected) > tol * scale then
				fail("expected ~" .. show(expected) .. ", got " .. show(actual))
			end
		end,
		toBeGreaterThan = function(expected: number)
			if not (actual > expected) then
				fail("expected " .. show(actual) .. " > " .. show(expected))
			end
		end,
		toBeGreaterThanOrEqual = function(expected: number)
			if not (actual >= expected) then
				fail("expected " .. show(actual) .. " >= " .. show(expected))
			end
		end,
		toBeLessThan = function(expected: number)
			if not (actual < expected) then
				fail("expected " .. show(actual) .. " < " .. show(expected))
			end
		end,
		toBeLessThanOrEqual = function(expected: number)
			if not (actual <= expected) then
				fail("expected " .. show(actual) .. " <= " .. show(expected))
			end
		end,
		toBeNil = function()
			if actual ~= nil then
				fail("expected nil, got " .. show(actual))
			end
		end,
		toBeTruthy = function()
			if not actual then
				fail("expected truthy, got " .. show(actual))
			end
		end,
		toBeFalsy = function()
			if actual then
				fail("expected falsy, got " .. show(actual))
			end
		end,
	}
end

return TestKit
