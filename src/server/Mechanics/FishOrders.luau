--!strict
-- Underwater (stub, world 3 is not enabled yet): fish customers tip big for
-- exactly the dish they ordered. Wire a "serve a different dish" UI to use
-- serveMultiplier when the world is turned on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dishes = require(Shared.Config.Dishes)
local Worlds = require(Shared.Config.Worlds)

local FishOrders = {}

function FishOrders.orderWeight(_dishId: string, _ctx: any): number
	return 1
end

function FishOrders.serveMultiplier(orderedDish: string, servedDish: string): number
	local config = Worlds.byId[Dishes.byId[orderedDish].world].fishOrders
	if config == nil then
		return 1
	end
	return if orderedDish == servedDish then config.correctTipMultiplier else config.wrongTipMultiplier
end

return FishOrders
