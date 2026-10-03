--!strict
-- Runs every tests/*.spec.luau file. Usage (from the repo root): lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")
local TestKit = require("./lib/TestKit")

local specs = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	local before = TestKit.results.failed
	require("./" .. string.gsub(name, "%.luau$", ""))
	local status = if TestKit.results.failed == before then "ok  " else "FAIL"
	print(status .. " " .. name)
end

for _, failure in TestKit.results.failures do
	print("\n✗ " .. failure.name .. "\n    " .. failure.message)
end
print(string.format("\n%d passed, %d failed", TestKit.results.passed, TestKit.results.failed))
if TestKit.results.failed > 0 then
	process.exit(1)
end
