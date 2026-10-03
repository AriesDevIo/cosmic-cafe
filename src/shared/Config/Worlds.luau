--!strict
-- World definitions. Each world has its own dishes, customers and a mechanic id
-- that the server's CafeService uses to pick a mechanic module (src/server/Mechanics).

export type Weather = {
	id: string,
	displayName: string,
	icon: string,
	tag: string, -- dishes with this tag are in demand during the rush
	valueMultiplier: number, -- applied to tagged dishes during the rush
	orderWeight: number, -- tagged dishes are this many times likelier to be ordered
}

export type WeatherConfig = {
	calmSeconds: number, -- time between rushes
	rushSeconds: number, -- rush duration
	weathers: { Weather },
}

export type FishOrdersConfig = {
	correctTipMultiplier: number,
	wrongTipMultiplier: number,
}

export type World = {
	id: string,
	index: number,
	displayName: string,
	description: string,
	mechanic: string, -- "Basic" | "Weather" | "FishOrders" | "Conveyor" | "TimeDilation"
	enabled: boolean, -- false = config stub, cannot be unlocked yet
	unlockCost: number,
	costGrowth: number,
	priceScale: number, -- multiplies staff hire / crate prices bought for this world
	dishes: { string },
	customers: { string },
	spawnInterval: number, -- seconds between customer spawns
	maxCustomers: number, -- customers waiting at once per plot
	color: Color3,
	weather: WeatherConfig?,
	fishOrders: FishOrdersConfig?,
}

local Worlds = {}

Worlds.order = { "StreetStall", "CloudCity", "Underwater", "MoonBase", "BlackHole" }

local list: { World } = {
	{
		id = "StreetStall",
		index = 1,
		displayName = "Street Stall",
		description = "Tap a station to cook, tap a customer to serve. Serve fast to build your tip streak!",
		mechanic = "Basic",
		enabled = true,
		unlockCost = 0,
		costGrowth = 1.07,
		priceScale = 1,
		dishes = { "Coffee", "Donut", "HotDog", "Pancakes", "Burger" },
		customers = {
			"Blorb",
			"Zibzab",
			"Glorp",
			"Squibbit",
			"Flumph",
			"MibMib",
			"Neb",
			"QuasarKid",
			"NebulaDuchess",
			"Zorbo",
		},
		spawnInterval = 2.0,
		maxCustomers = 4,
		color = Color3.fromRGB(255, 170, 90),
	},
	{
		id = "CloudCity",
		index = 2,
		displayName = "Cloud City",
		description = "Weather rushes! Rain makes everyone crave hot drinks, sunshine sells smoothies.",
		mechanic = "Weather",
		enabled = true,
		unlockCost = 2.5e6,
		costGrowth = 1.08,
		priceScale = 2e4,
		dishes = { "HotCocoa", "BerrySmoothie", "CloudTea", "RainbowSundae", "StormSoup" },
		customers = {
			"Puffle",
			"Driftling",
			"NimbusNomad",
			"ZephyrZee",
			"SkySquid",
			"Thunderbelly",
			"PrismMoth",
			"AuroraEmpress",
		},
		spawnInterval = 1.8,
		maxCustomers = 5,
		color = Color3.fromRGB(150, 200, 255),
		weather = {
			calmSeconds = 45,
			rushSeconds = 25,
			weathers = {
				{
					id = "Rain",
					displayName = "Rain Rush",
					icon = "🌧️",
					tag = "Hot",
					valueMultiplier = 3,
					orderWeight = 4,
				},
				{
					id = "Sun",
					displayName = "Sunshine Rush",
					icon = "☀️",
					tag = "Cold",
					valueMultiplier = 3,
					orderWeight = 4,
				},
			},
		},
	},
	{
		id = "Underwater",
		index = 3,
		displayName = "Underwater Diner",
		description = "Fish customers want exactly what they ordered. Get it right for a huge tip.",
		mechanic = "FishOrders",
		enabled = false,
		unlockCost = 5e12,
		costGrowth = 1.12,
		priceScale = 2e10,
		dishes = { "KelpRoll", "SeaFoamLatte", "CoralCake" },
		customers = {},
		spawnInterval = 2.0,
		maxCustomers = 5,
		color = Color3.fromRGB(40, 120, 200),
		fishOrders = {
			correctTipMultiplier = 4,
			wrongTipMultiplier = 0.25,
		},
	},
	{
		id = "MoonBase",
		index = 4,
		displayName = "Moon Base",
		description = "Conveyor belts and low-gravity deliveries.",
		mechanic = "Conveyor",
		enabled = false,
		unlockCost = 5e18,
		costGrowth = 1.13,
		priceScale = 2e16,
		dishes = { "CraterCheese", "MoonPie", "RocketFries" },
		customers = {},
		spawnInterval = 2.0,
		maxCustomers = 5,
		color = Color3.fromRGB(200, 200, 210),
	},
	{
		id = "BlackHole",
		index = 5,
		displayName = "Black Hole Bistro",
		description = "Time dilation: chain orders into combos before time catches up.",
		mechanic = "TimeDilation",
		enabled = false,
		unlockCost = 5e25,
		costGrowth = 1.15,
		priceScale = 2e23,
		dishes = { "QuantumNoodles", "SingularitySoda", "EventHorizonPie" },
		customers = {},
		spawnInterval = 2.0,
		maxCustomers = 5,
		color = Color3.fromRGB(90, 40, 140),
	},
}

Worlds.list = list
Worlds.byId = {} :: { [string]: World }
for _, world in list do
	Worlds.byId[world.id] = world
end

Worlds.first = list[1].id

function Worlds.next(worldId: string): World?
	local world = Worlds.byId[worldId]
	if not world then
		return nil
	end
	return list[world.index + 1]
end

return Worlds
