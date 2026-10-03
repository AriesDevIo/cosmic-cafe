--!strict
-- Number formatting for incremental-game sized values.
--
-- Money is stored as a plain double (enough up to ~1.8e308). Formatting covers
-- 1.2K, 3.4M ... up to 1e303 ("Ce") with short-scale suffixes, then scientific
-- notation. For values past the double range use the mantissa/exponent BigNum
-- type below (m * 10^e, 1 <= |m| < 10).

local BigNum = {}

export type BigNum = {
	m: number,
	e: number,
}

local FIRST = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
local UNITS = { "", "U", "D", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
local TENS = { "", "Dc", "Vg", "Tg", "Qag", "Qig", "Sxg", "Spg", "Ocg", "Nog" }

-- SUFFIXES[n] is the suffix for 10^(3n).
local SUFFIXES: { string } = {}
for n = 1, 101 do
	if n <= #FIRST then
		SUFFIXES[n] = FIRST[n]
	elseif n == 101 then
		SUFFIXES[n] = "Ce"
	else
		local illion = n - 1 -- 1e6 is the 1st -illion
		SUFFIXES[n] = UNITS[illion % 10 + 1] .. TENS[illion // 10 + 1]
	end
end
BigNum.suffixes = SUFFIXES

local MAX_SUFFIXED_EXPONENT = #SUFFIXES * 3 + 2 -- 999.99Ce

-- Drops trailing zeros: "1.50" -> "1.5", "2.00" -> "2".
local function trim(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Formats a mantissa with `digits` significant digits (at most 2 decimals).
local function mantissaString(value: number, digits: number): string
	local decimals = math.clamp(digits - #tostring(math.floor(math.abs(value))), 0, 2)
	local factor = 10 ^ decimals
	local rounded = math.floor(value * factor + 1e-6) / factor -- floor: never show more than you have
	return trim(string.format("%." .. decimals .. "f", rounded))
end

-- Formats a value from its base-10 log; works for numbers far beyond 1e308.
function BigNum.formatLog(log10: number, negative: boolean?): string
	local sign = if negative then "-" else ""
	if log10 ~= log10 then
		return "NaN"
	end
	if log10 == math.huge then
		return sign .. "∞"
	end
	local exponent = math.floor(log10 + 1e-9)
	if exponent < 3 then
		return sign .. tostring(math.floor(10 ^ log10 + 1e-9))
	end
	if exponent > MAX_SUFFIXED_EXPONENT then
		local mantissa = 10 ^ (log10 - exponent)
		return sign .. mantissaString(mantissa, 3) .. "e" .. exponent
	end
	local group = exponent // 3
	return sign .. mantissaString(10 ^ (log10 - group * 3), 3) .. SUFFIXES[group]
end

-- 950 -> "950", 1234 -> "1.23K", 3.4e6 -> "3.4M", 1e306 -> "1e306".
function BigNum.format(value: number): string
	if value ~= value then
		return "NaN"
	end
	local negative = value < 0
	local magnitude = math.abs(value)
	if magnitude == math.huge then
		return (if negative then "-" else "") .. "∞"
	end
	if magnitude < 1000 then
		local whole = math.floor(magnitude + 1e-9)
		if magnitude < 10 and magnitude ~= whole then
			-- small fractional values (income/s) keep one decimal
			local text = trim(string.format("%.1f", math.floor(magnitude * 10 + 1e-9) / 10))
			return (if negative then "-" else "") .. text
		end
		return (if negative then "-" else "") .. tostring(whole)
	end
	local exponent = math.floor(math.log10(magnitude) + 1e-9)
	if exponent > MAX_SUFFIXED_EXPONENT then
		return BigNum.formatLog(math.log10(magnitude), negative)
	end
	-- divide instead of using the log so exact values (1000, 1e6) stay exact
	local group = exponent // 3
	local scaled = magnitude / 10 ^ (group * 3)
	if scaled < 1 then
		group -= 1
		scaled = magnitude / 10 ^ (group * 3)
	end
	return (if negative then "-" else "") .. mantissaString(scaled, 3) .. SUFFIXES[group]
end

-- "$1.23K"
function BigNum.money(value: number): string
	if value < 0 then
		return "-$" .. BigNum.format(-value)
	end
	return "$" .. BigNum.format(value)
end

-- "1.23K/s"
function BigNum.rate(value: number): string
	return BigNum.format(value) .. "/s"
end

-- Seconds -> "1h 05m", "4m 09s", "12s".
function BigNum.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- Mantissa/exponent numbers -------------------------------------------------

local function normalize(m: number, e: number): BigNum
	if m == 0 then
		return { m = 0, e = 0 }
	end
	local shift = math.floor(math.log10(math.abs(m)))
	return { m = m / 10 ^ shift, e = e + shift }
end

function BigNum.new(m: number, e: number): BigNum
	return normalize(m, e)
end

function BigNum.fromNumber(value: number): BigNum
	return normalize(value, 0)
end

function BigNum.toNumber(value: BigNum): number
	return value.m * 10 ^ value.e
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
	if a.m == 0 then
		return b
	elseif b.m == 0 then
		return a
	end
	local big, small = a, b
	if b.e > a.e then
		big, small = b, a
	end
	local diff = big.e - small.e
	if diff > 17 then
		return big -- beyond double precision
	end
	return normalize(big.m + small.m / 10 ^ diff, big.e)
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
	return BigNum.add(a, { m = -b.m, e = b.e })
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
	return normalize(a.m * b.m, a.e + b.e)
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
	assert(b.m ~= 0, "BigNum division by zero")
	return normalize(a.m / b.m, a.e - b.e)
end

-- -1, 0 or 1
function BigNum.compare(a: BigNum, b: BigNum): number
	local signA = if a.m > 0 then 1 elseif a.m < 0 then -1 else 0
	local signB = if b.m > 0 then 1 elseif b.m < 0 then -1 else 0
	if signA ~= signB then
		return if signA > signB then 1 else -1
	end
	if signA == 0 then
		return 0
	end
	if a.e ~= b.e then
		local bigger = if a.e > b.e then 1 else -1
		return bigger * signA
	end
	if a.m == b.m then
		return 0
	end
	return if a.m > b.m then 1 else -1
end

function BigNum.log10(value: BigNum): number
	return math.log10(math.abs(value.m)) + value.e
end

function BigNum.formatBig(value: BigNum): string
	if value.m == 0 then
		return "0"
	end
	return BigNum.formatLog(BigNum.log10(value), value.m < 0)
end

return BigNum
