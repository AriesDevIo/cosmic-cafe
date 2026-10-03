--!strict
-- Street Stall: every unlocked dish is equally likely, you serve what was ordered.

local Basic = {}

function Basic.orderWeight(_dishId: string, _ctx: any): number
	return 1
end

function Basic.serveMultiplier(_orderedDish: string, _servedDish: string): number
	return 1
end

return Basic
