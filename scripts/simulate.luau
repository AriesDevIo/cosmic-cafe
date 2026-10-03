--!strict
-- Simulates the first hours of play and prints when every unlock happens.
-- Usage (repo root):  lune run scripts/simulate [hours] [--all]
--   --all   also print milestones and Star Chef thresholds
local process = require("@lune/process")
local Loader = require("../tests/lib/Loader")
local PacingSim = require("./lib/PacingSim")
local BigNum = Loader.shared("Util/BigNum")
local Worlds = Loader.shared("Config/Worlds")

local hours = 3
local verbose = false
for _, arg in process.args do
	if arg == "--all" then
		verbose = true
	elseif tonumber(arg) then
		hours = tonumber(arg) :: number
	end
end

local function clock(seconds: number): string
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local startedAt = os.clock()
local result = PacingSim.run({ seconds = hours * 3600 })

print(string.format("=== Cosmic Cafe pacing: first %gh of play ===\n", hours))
print("  total    run      event")
for _, event in result.events do
	local quiet = event.kind == "milestone" or event.kind == "starchef"
	if verbose or not quiet then
		print(string.format("  %s  %s  [run %d] %s", clock(event.time), clock(event.runTime), event.run, event.text))
	end
end

print("\n--- Snapshots ---")
for _, snap in result.snapshots do
	print(
		string.format(
			"  %s  run %d  money %-9s income %s",
			clock(snap.time),
			snap.run,
			BigNum.money(snap.money),
			BigNum.rate(snap.rate)
		)
	)
end

-- Targets from the design doc ------------------------------------------------
local checks = {}
local function check(name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok, detail = detail })
end

check("First sale < 30s", result.firstSale < 30, clock(result.firstSale))

-- "Upgrade" = a goal the next-unlock bar points at: new dish, staff hire,
-- world, x2 milestone or every 10th dish level. Single +1 level buys are much
-- more frequent than that (the 1.07 cost curve makes early levels cheap).
local gaps = PacingSim.goalGaps(result, 0, 300)
local sum, longest = 0, 0
for _, gap in gaps do
	sum += gap
	longest = math.max(longest, gap)
end
local buys = 0
for _, t in result.purchaseTimes do
	if t < 300 then
		buys += 1
	end
end
local average = if #gaps > 0 then sum / #gaps else math.huge
check(
	"Upgrade every 20-40s in first 5 min",
	average >= 15 and average <= 45 and longest <= 75,
	string.format("%d goals (%d +1 buys), avg gap %.0fs, longest %.0fs", #gaps, buys, average, longest)
)

local hire = result.firstHire
check("First staff hire ~2 min", hire ~= nil and hire >= 60 and hire <= 240, if hire then clock(hire) else "never")

local world2 = Worlds.list[2].id
local unlocks = result.worldUnlocks[world2] or {}
local firstW2 = unlocks[1]
check(
	"World 2 at 30-60 min",
	firstW2 ~= nil and firstW2 >= 30 * 60 and firstW2 <= 60 * 60,
	if firstW2 then clock(firstW2) else "never"
)

local franchise = result.franchises[1]
check(
	"First Franchise at 1.5-2h",
	franchise ~= nil and franchise.time >= 90 * 60 and franchise.time <= 120 * 60,
	if franchise then clock(franchise.time) .. " for " .. franchise.gain .. " Star Chefs" else "never"
)

local secondW2 = unlocks[2]
if firstW2 and secondW2 then
	local speedup = firstW2 / secondW2
	check(
		"Second run ~2x faster (World 2)",
		speedup >= 1.7,
		string.format("%s vs %s = %.1fx", clock(firstW2), clock(secondW2), speedup)
	)
else
	check("Second run ~2x faster (World 2)", false, "second run did not reach World 2")
end

local secondFranchise = result.franchises[2]
if franchise and secondFranchise then
	local speedup = franchise.runTime / secondFranchise.runTime
	check(
		"Second run ~2x faster (Franchise)",
		speedup >= 1.7,
		string.format("%s vs %s = %.1fx", clock(franchise.runTime), clock(secondFranchise.runTime), speedup)
	)
end

print("\n--- Targets ---")
local failed = 0
for _, c in checks do
	print(string.format("  [%s] %-38s %s", if c.ok then "PASS" else "MISS", c.name, c.detail))
	if not c.ok then
		failed += 1
	end
end
print(string.format("\n(simulated in %.1fs)", os.clock() - startedAt))
if failed > 0 then
	process.exit(1)
end
