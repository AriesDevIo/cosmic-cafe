--!strict
-- Cloud City: during a weather rush customers crave dishes with the rush's tag
-- (Stats applies the value multiplier through ctx.weather).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dishes = require(Shared.Config.Dishes)
local Worlds = require(Shared.Config.Worlds)
local Types = require(Shared.Types)

local Weather = {}

function Weather.orderWeight(dishId: string, ctx: Types.Context): number
	if ctx.weather == nil then
		return 1
	end
	local dish = Dishes.byId[dishId]
	local config = Worlds.byId[dish.world].weather
	if config == nil then
		return 1
	end
	for _, weather in config.weathers do
		if weather.id == ctx.weather and table.find(dish.tags, weather.tag) then
			return weather.orderWeight
		end
	end
	return 1
end

function Weather.serveMultiplier(_orderedDish: string, _servedDish: string): number
	return 1
end

return Weather
