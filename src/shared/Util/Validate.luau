--!strict
-- Remote argument validation. Everything coming from a client is `unknown`
-- until one of these says otherwise.

local Validate = {}

function Validate.string(value: unknown, maxLength: number?): boolean
	return type(value) == "string" and #value > 0 and #value <= (maxLength or 64)
end

function Validate.integer(value: unknown, min: number, max: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

function Validate.boolean(value: unknown): boolean
	return type(value) == "boolean"
end

-- A plain array of short strings with 1..maxCount entries.
function Validate.stringArray(value: unknown, maxCount: number, maxLength: number?): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, item in value :: { [unknown]: unknown } do
		count += 1
		if type(key) ~= "number" or not Validate.string(item, maxLength) then
			return false
		end
	end
	return count >= 1 and count <= maxCount and #(value :: { unknown }) == count
end

-- True if `value` is a key of `map` (and a valid string).
function Validate.oneOf(value: unknown, map: { [string]: any }): boolean
	return Validate.string(value) and map[value :: string] ~= nil
end

return Validate
