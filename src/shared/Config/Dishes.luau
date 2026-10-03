--!strict
-- Dish (station) definitions. A dish's level is bought with money; each level
-- adds `baseIncome` to the value of one serving. Cost of the next level is
-- baseCost * world.costGrowth ^ levelsOwned.

export type Dish = {
	id: string,
	displayName: string,
	icon: string,
	world: string,
	baseCost: number,
	baseIncome: number, -- value of one serving per level
	cookTime: number, -- seconds per serving at speed multiplier 1
	tags: { string }, -- used by world mechanics (e.g. "Hot"/"Cold" for weather)
}

export type Milestone = {
	level: number,
	speedMultiplier: number,
}

export type Ingredient = {
	id: string,
	displayName: string,
	icon: string,
	world: string, -- world that must be unlocked to use it
}

export type RecipeBonus = {
	dish: string?, -- multiply this dish's serving value
	valueMultiplier: number?,
	globalIncome: number?, -- additive bonus to the global income multiplier
}

export type Recipe = {
	id: string,
	displayName: string,
	icon: string,
	ingredients: { string }, -- sorted ingredient ids
	bonus: RecipeBonus,
}

local Dishes = {}

-- Reaching a milestone level multiplies the dish's cook speed.
Dishes.milestones = {
	{ level = 25, speedMultiplier = 2 },
	{ level = 50, speedMultiplier = 2 },
	{ level = 100, speedMultiplier = 2 },
	{ level = 200, speedMultiplier = 2 },
} :: { Milestone }

local list: { Dish } = {
	-- World 1: Street Stall
	{
		id = "Coffee",
		displayName = "Coffee",
		icon = "☕",
		world = "StreetStall",
		baseCost = 6,
		baseIncome = 1,
		cookTime = 2,
		tags = { "Hot" },
	},
	{
		id = "Donut",
		displayName = "Donut",
		icon = "🍩",
		world = "StreetStall",
		baseCost = 90,
		baseIncome = 9,
		cookTime = 4,
		tags = {},
	},
	{
		id = "HotDog",
		displayName = "Hot Dog",
		icon = "🌭",
		world = "StreetStall",
		baseCost = 1350,
		baseIncome = 80,
		cookTime = 8,
		tags = { "Hot" },
	},
	{
		id = "Pancakes",
		displayName = "Pancakes",
		icon = "🥞",
		world = "StreetStall",
		baseCost = 20000,
		baseIncome = 720,
		cookTime = 16,
		tags = { "Hot" },
	},
	{
		id = "Burger",
		displayName = "Burger",
		icon = "🍔",
		world = "StreetStall",
		baseCost = 300000,
		baseIncome = 6500,
		cookTime = 32,
		tags = { "Hot" },
	},

	-- World 2: Cloud City
	{
		id = "HotCocoa",
		displayName = "Hot Cocoa",
		icon = "🍫",
		world = "CloudCity",
		baseCost = 1.2e6,
		baseIncome = 1e4,
		cookTime = 2,
		tags = { "Hot" },
	},
	{
		id = "BerrySmoothie",
		displayName = "Berry Smoothie",
		icon = "🥤",
		world = "CloudCity",
		baseCost = 1.8e7,
		baseIncome = 9e4,
		cookTime = 4,
		tags = { "Cold" },
	},
	{
		id = "CloudTea",
		displayName = "Cloud Tea",
		icon = "🍵",
		world = "CloudCity",
		baseCost = 2.72e8,
		baseIncome = 8.1e5,
		cookTime = 8,
		tags = { "Hot" },
	},
	{
		id = "RainbowSundae",
		displayName = "Rainbow Sundae",
		icon = "🍨",
		world = "CloudCity",
		baseCost = 4e9,
		baseIncome = 7.3e6,
		cookTime = 16,
		tags = { "Cold" },
	},
	{
		id = "StormSoup",
		displayName = "Storm Soup",
		icon = "🍲",
		world = "CloudCity",
		baseCost = 6.08e10,
		baseIncome = 6.6e7,
		cookTime = 32,
		tags = { "Hot" },
	},

	-- World 3: Underwater (stub)
	{
		id = "KelpRoll",
		displayName = "Kelp Roll",
		icon = "🍣",
		world = "Underwater",
		baseCost = 1e13,
		baseIncome = 2e11,
		cookTime = 2,
		tags = { "Fish" },
	},
	{
		id = "SeaFoamLatte",
		displayName = "Sea Foam Latte",
		icon = "🧋",
		world = "Underwater",
		baseCost = 2e14,
		baseIncome = 2e12,
		cookTime = 5,
		tags = { "Hot" },
	},
	{
		id = "CoralCake",
		displayName = "Coral Cake",
		icon = "🍰",
		world = "Underwater",
		baseCost = 4e15,
		baseIncome = 2e13,
		cookTime = 12,
		tags = {},
	},

	-- World 4: Moon Base (stub)
	{
		id = "CraterCheese",
		displayName = "Crater Cheese",
		icon = "🧀",
		world = "MoonBase",
		baseCost = 1e19,
		baseIncome = 2e17,
		cookTime = 2,
		tags = {},
	},
	{
		id = "MoonPie",
		displayName = "Moon Pie",
		icon = "🥧",
		world = "MoonBase",
		baseCost = 3e20,
		baseIncome = 3e18,
		cookTime = 6,
		tags = {},
	},
	{
		id = "RocketFries",
		displayName = "Rocket Fries",
		icon = "🍟",
		world = "MoonBase",
		baseCost = 9e21,
		baseIncome = 4e19,
		cookTime = 15,
		tags = { "Hot" },
	},

	-- World 5: Black Hole (stub)
	{
		id = "QuantumNoodles",
		displayName = "Quantum Noodles",
		icon = "🍜",
		world = "BlackHole",
		baseCost = 1e26,
		baseIncome = 2e24,
		cookTime = 3,
		tags = { "Hot" },
	},
	{
		id = "SingularitySoda",
		displayName = "Singularity Soda",
		icon = "🧃",
		world = "BlackHole",
		baseCost = 5e27,
		baseIncome = 5e25,
		cookTime = 8,
		tags = { "Cold" },
	},
	{
		id = "EventHorizonPie",
		displayName = "Event Horizon Pie",
		icon = "🥮",
		world = "BlackHole",
		baseCost = 2e29,
		baseIncome = 1e27,
		cookTime = 20,
		tags = {},
	},
}

Dishes.list = list
Dishes.byId = {} :: { [string]: Dish }
for _, dish in list do
	Dishes.byId[dish.id] = dish
end

Dishes.ingredients = {
	{ id = "Bean", displayName = "Star Bean", icon = "🫘", world = "StreetStall" },
	{ id = "Milk", displayName = "Moo-on Milk", icon = "🥛", world = "StreetStall" },
	{ id = "Sugar", displayName = "Comet Sugar", icon = "🧂", world = "StreetStall" },
	{ id = "Flour", displayName = "Flour", icon = "🌾", world = "StreetStall" },
	{ id = "Egg", displayName = "Space Egg", icon = "🥚", world = "StreetStall" },
	{ id = "Cocoa", displayName = "Cocoa", icon = "🍫", world = "StreetStall" },
	{ id = "Stardust", displayName = "Stardust", icon = "✨", world = "StreetStall" },
	{ id = "Berry", displayName = "Sky Berry", icon = "🫐", world = "CloudCity" },
	{ id = "Ice", displayName = "Hail Ice", icon = "🧊", world = "CloudCity" },
	{ id = "Cloud", displayName = "Cloud Fluff", icon = "☁️", world = "CloudCity" },
} :: { Ingredient }

Dishes.ingredientById = {} :: { [string]: Ingredient }
for _, ingredient in Dishes.ingredients do
	Dishes.ingredientById[ingredient.id] = ingredient
end

Dishes.maxRecipeIngredients = 3

local recipes: { Recipe } = {
	{
		id = "Latte",
		displayName = "Galaxy Latte",
		icon = "☕",
		ingredients = { "Bean", "Milk" },
		bonus = { dish = "Coffee", valueMultiplier = 1.5 },
	},
	{
		id = "GlazedRing",
		displayName = "Glazed Ring",
		icon = "🍩",
		ingredients = { "Flour", "Sugar" },
		bonus = { dish = "Donut", valueMultiplier = 1.5 },
	},
	{
		id = "FluffyStack",
		displayName = "Fluffy Stack",
		icon = "🥞",
		ingredients = { "Egg", "Flour", "Milk" },
		bonus = { dish = "Pancakes", valueMultiplier = 1.5 },
	},
	{
		id = "CosmicMocha",
		displayName = "Cosmic Mocha",
		icon = "🌌",
		ingredients = { "Bean", "Cocoa", "Stardust" },
		bonus = { globalIncome = 0.05 },
	},
	{
		id = "BerryBlast",
		displayName = "Berry Blast",
		icon = "🥤",
		ingredients = { "Berry", "Ice" },
		bonus = { dish = "BerrySmoothie", valueMultiplier = 1.5 },
	},
	{
		id = "CloudPuff",
		displayName = "Cloud Puff",
		icon = "☁️",
		ingredients = { "Cloud", "Sugar" },
		bonus = { dish = "CloudTea", valueMultiplier = 1.5 },
	},
	{
		id = "StormBrew",
		displayName = "Storm Brew",
		icon = "⛈️",
		ingredients = { "Bean", "Cloud", "Cocoa" },
		bonus = { dish = "HotCocoa", valueMultiplier = 1.5 },
	},
	{
		id = "NebulaSundae",
		displayName = "Nebula Sundae",
		icon = "🍨",
		ingredients = { "Berry", "Ice", "Stardust" },
		bonus = { globalIncome = 0.05 },
	},
}

for _, recipe in recipes do
	table.sort(recipe.ingredients)
end

Dishes.recipes = recipes
Dishes.recipeById = {} :: { [string]: Recipe }
for _, recipe in recipes do
	Dishes.recipeById[recipe.id] = recipe
end

return Dishes
