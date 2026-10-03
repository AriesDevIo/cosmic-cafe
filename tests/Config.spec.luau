-- Integrity checks: every id referenced in config exists.
local Loader = require("./lib/Loader")
local TestKit = require("./lib/TestKit")
local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

local Customers = Loader.shared("Config/Customers")
local Dishes = Loader.shared("Config/Dishes")
local Economy = Loader.shared("Config/Economy")
local Franchise = Loader.shared("Config/Franchise")
local Staff = Loader.shared("Config/Staff")
local Worlds = Loader.shared("Config/Worlds")

describe("Worlds config", function()
	it("lists every world in order", function()
		expect(#Worlds.order).toBe(#Worlds.list)
		for index, id in Worlds.order do
			expect(Worlds.byId[id].index).toBe(index)
			expect(Worlds.list[index].id).toBe(id)
		end
	end)

	it("references existing dishes of the same world", function()
		for _, world in Worlds.list do
			expect(#world.dishes).toBeGreaterThan(0)
			for _, dishId in world.dishes do
				local dish = Dishes.byId[dishId]
				expect(dish ~= nil).toBeTruthy()
				expect(dish.world).toBe(world.id)
			end
		end
	end)

	it("references existing, non-special customers", function()
		for _, world in Worlds.list do
			for _, speciesId in world.customers do
				local species = Customers.byId[speciesId]
				expect(species ~= nil).toBeTruthy()
				expect(species.special).toBeFalsy()
			end
		end
	end)

	it("makes worlds 1 and 2 playable and 3-5 stubs", function()
		expect(Worlds.list[1].enabled).toBe(true)
		expect(Worlds.list[2].enabled).toBe(true)
		for index = 3, 5 do
			expect(Worlds.list[index].enabled).toBe(false)
		end
	end)

	it("gets more expensive world by world", function()
		for index = 2, #Worlds.list do
			expect(Worlds.list[index].unlockCost).toBeGreaterThan(Worlds.list[index - 1].unlockCost)
			expect(Worlds.list[index].costGrowth).toBeGreaterThanOrEqual(Worlds.list[index - 1].costGrowth)
		end
	end)

	it("uses steeper growth from world 3", function()
		for index = 3, #Worlds.list do
			expect(Worlds.list[index].costGrowth).toBeGreaterThanOrEqual(1.12)
			expect(Worlds.list[index].costGrowth).toBeLessThanOrEqual(1.15)
		end
	end)

	it("configures the world mechanics", function()
		expect(Worlds.byId.CloudCity.weather ~= nil).toBeTruthy()
		expect(Worlds.byId.Underwater.fishOrders ~= nil).toBeTruthy()
	end)
end)

describe("Dishes config", function()
	it("belongs to known worlds and has sane numbers", function()
		for _, dish in Dishes.list do
			expect(Worlds.byId[dish.world] ~= nil).toBeTruthy()
			expect(dish.baseCost).toBeGreaterThan(0)
			expect(dish.baseIncome).toBeGreaterThan(0)
			expect(dish.cookTime).toBeGreaterThan(0)
		end
	end)

	it("has CloudCity dishes for both weathers", function()
		local tags = {}
		for _, dishId in Worlds.byId.CloudCity.dishes do
			for _, tag in Dishes.byId[dishId].tags do
				tags[tag] = true
			end
		end
		for _, weather in Worlds.byId.CloudCity.weather.weathers do
			expect(tags[weather.tag]).toBe(true)
		end
	end)

	it("has milestones at 25/50/100/200 doubling speed", function()
		local levels = {}
		for _, milestone in Dishes.milestones do
			table.insert(levels, milestone.level)
			expect(milestone.speedMultiplier).toBe(2)
		end
		expect(levels).toEqual({ 25, 50, 100, 200 })
	end)

	it("has valid, unique recipes", function()
		local keys = {}
		for _, recipe in Dishes.recipes do
			expect(#recipe.ingredients >= 2 and #recipe.ingredients <= Dishes.maxRecipeIngredients).toBeTruthy()
			for _, ingredientId in recipe.ingredients do
				expect(Dishes.ingredientById[ingredientId] ~= nil).toBeTruthy()
			end
			local key = table.concat(recipe.ingredients, "+")
			expect(keys[key]).toBeNil()
			keys[key] = true
			if recipe.bonus.dish then
				expect(Dishes.byId[recipe.bonus.dish] ~= nil).toBeTruthy()
			end
		end
	end)
end)

describe("Customers config", function()
	it("has 20 species with known rarities", function()
		expect(#Customers.list).toBe(20)
		for _, species in Customers.list do
			expect(Customers.rarities[species.rarity] ~= nil).toBeTruthy()
			expect(species.tipMultiplier).toBeGreaterThan(0)
		end
	end)

	it("has the Golden Alien and Food Critic", function()
		expect(Customers.byId[Customers.goldenId].special).toBe(true)
		expect(Customers.byId[Customers.criticId].special).toBe(true)
		expect(Economy.golden.chance).toBeCloseTo(1 / 500)
	end)
end)

describe("Staff config", function()
	it("has every role and rarity in order lists", function()
		for _, roleId in Staff.roleOrder do
			expect(Staff.roles[roleId] ~= nil).toBeTruthy()
		end
		local last = 0
		for _, rarityId in Staff.rarityOrder do
			local rarity = Staff.rarities[rarityId]
			expect(rarity.multiplier).toBeGreaterThan(last)
			last = rarity.multiplier
		end
		expect(Staff.rarityOrder).toEqual({ "Common", "Rare", "Epic", "Legendary", "Cosmic" })
	end)

	it("only rolls known rarities and roles from crates", function()
		for _, crate in Staff.crates do
			for rarityId in crate.odds do
				expect(Staff.rarities[rarityId] ~= nil).toBeTruthy()
			end
		end
		for roleId in Staff.crateRoleWeights do
			expect(Staff.roles[roleId] ~= nil).toBeTruthy()
			expect(Staff.roles[roleId].global).toBe(false)
		end
	end)
end)

describe("Franchise config", function()
	it("only requires existing nodes", function()
		for _, node in Franchise.nodes do
			expect(node.cost).toBeGreaterThan(0)
			for _, required in node.requires do
				expect(Franchise.byId[required] ~= nil).toBeTruthy()
			end
		end
	end)

	it("can reach the 12h offline cap", function()
		local hours = Economy.offline.baseCapHours
		for _, node in Franchise.nodes do
			hours += node.offlineHours or 0
		end
		expect(hours).toBe(Economy.offline.maxCapHours)
	end)
end)
