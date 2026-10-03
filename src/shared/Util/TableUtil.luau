--!strict
-- Small table helpers used for save data.

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[TableUtil.deepCopy(key)] = TableUtil.deepCopy(child)
	end
	return (copy :: any) :: T
end

-- Fills in every key of `template` that is missing from `target` (recursively).
-- Keys in `target` that the template does not know are kept.
function TableUtil.reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		local existing = target[key]
		if type(existing) == "table" and type(value) == "table" then
			TableUtil.reconcile(existing, value)
		elseif existing == nil or type(existing) ~= type(value) then
			-- missing, or corrupted / renamed field: use the template value
			target[key] = TableUtil.deepCopy(value)
		end
	end
end

function TableUtil.count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

return TableUtil
