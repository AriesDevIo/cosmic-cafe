--!strict
-- Alien customer species. A customer's tip multiplies the value of the dish served.

export type Rarity = {
	id: string,
	weight: number, -- relative spawn weight inside a world
	color: Color3,
	announce: boolean, -- announce discoveries/serves to the whole server
}

export type Species = {
	id: string,
	displayName: string,
	rarity: string,
	tipMultiplier: number,
	color: Color3,
	icon: string,
	special: boolean?, -- never rolled normally (Golden Alien, Food Critic)
}

local Customers = {}

Customers.rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Customers.rarities = {
	Common = { id = "Common", weight = 60, color = Color3.fromRGB(200, 200, 200), announce = false },
	Uncommon = { id = "Uncommon", weight = 25, color = Color3.fromRGB(110, 220, 120), announce = false },
	Rare = { id = "Rare", weight = 10, color = Color3.fromRGB(90, 160, 255), announce = false },
	Epic = { id = "Epic", weight = 4, color = Color3.fromRGB(190, 100, 255), announce = false },
	Legendary = { id = "Legendary", weight = 1, color = Color3.fromRGB(255, 190, 40), announce = true },
	Mythic = { id = "Mythic", weight = 0, color = Color3.fromRGB(255, 230, 80), announce = true },
} :: { [string]: Rarity }

Customers.goldenId = "GoldenAlien"
Customers.criticId = "FoodCritic"

local list: { Species } = {
	-- Street Stall regulars
	{
		id = "Blorb",
		displayName = "Blorb",
		rarity = "Common",
		tipMultiplier = 1.0,
		color = Color3.fromRGB(120, 230, 120),
		icon = "👽",
	},
	{
		id = "Zibzab",
		displayName = "Zibzab",
		rarity = "Common",
		tipMultiplier = 1.0,
		color = Color3.fromRGB(230, 120, 200),
		icon = "👾",
	},
	{
		id = "Glorp",
		displayName = "Glorp",
		rarity = "Common",
		tipMultiplier = 1.05,
		color = Color3.fromRGB(120, 200, 230),
		icon = "🫠",
	},
	{
		id = "Squibbit",
		displayName = "Squibbit",
		rarity = "Uncommon",
		tipMultiplier = 1.25,
		color = Color3.fromRGB(250, 160, 80),
		icon = "🐙",
	},
	{
		id = "Flumph",
		displayName = "Flumph",
		rarity = "Uncommon",
		tipMultiplier = 1.25,
		color = Color3.fromRGB(180, 140, 255),
		icon = "🪼",
	},
	{
		id = "MibMib",
		displayName = "Mib Mib",
		rarity = "Rare",
		tipMultiplier = 1.6,
		color = Color3.fromRGB(80, 120, 255),
		icon = "🤖",
	},
	{
		id = "Neb",
		displayName = "Neb",
		rarity = "Rare",
		tipMultiplier = 1.6,
		color = Color3.fromRGB(255, 90, 90),
		icon = "👹",
	},
	{
		id = "QuasarKid",
		displayName = "Quasar Kid",
		rarity = "Epic",
		tipMultiplier = 2.5,
		color = Color3.fromRGB(200, 80, 255),
		icon = "🌟",
	},
	{
		id = "NebulaDuchess",
		displayName = "Nebula Duchess",
		rarity = "Legendary",
		tipMultiplier = 5,
		color = Color3.fromRGB(255, 120, 220),
		icon = "👑",
	},
	{
		id = "Zorbo",
		displayName = "Zorbo",
		rarity = "Common",
		tipMultiplier = 1.0,
		color = Color3.fromRGB(200, 200, 90),
		icon = "🛸",
	},

	-- Cloud City locals
	{
		id = "Puffle",
		displayName = "Puffle",
		rarity = "Common",
		tipMultiplier = 1.0,
		color = Color3.fromRGB(240, 240, 255),
		icon = "☁️",
	},
	{
		id = "Driftling",
		displayName = "Driftling",
		rarity = "Common",
		tipMultiplier = 1.05,
		color = Color3.fromRGB(200, 230, 255),
		icon = "🎈",
	},
	{
		id = "NimbusNomad",
		displayName = "Nimbus Nomad",
		rarity = "Uncommon",
		tipMultiplier = 1.25,
		color = Color3.fromRGB(160, 180, 220),
		icon = "🌫️",
	},
	{
		id = "ZephyrZee",
		displayName = "Zephyr Zee",
		rarity = "Uncommon",
		tipMultiplier = 1.25,
		color = Color3.fromRGB(150, 255, 220),
		icon = "🌀",
	},
	{
		id = "SkySquid",
		displayName = "Sky Squid",
		rarity = "Rare",
		tipMultiplier = 1.6,
		color = Color3.fromRGB(255, 150, 180),
		icon = "🦑",
	},
	{
		id = "Thunderbelly",
		displayName = "Thunderbelly",
		rarity = "Rare",
		tipMultiplier = 1.6,
		color = Color3.fromRGB(255, 230, 90),
		icon = "⚡",
	},
	{
		id = "PrismMoth",
		displayName = "Prism Moth",
		rarity = "Epic",
		tipMultiplier = 2.5,
		color = Color3.fromRGB(180, 255, 255),
		icon = "🦋",
	},
	{
		id = "AuroraEmpress",
		displayName = "Aurora Empress",
		rarity = "Legendary",
		tipMultiplier = 5,
		color = Color3.fromRGB(120, 255, 180),
		icon = "🌈",
	},

	-- Specials (any world)
	{
		id = "GoldenAlien",
		displayName = "Golden Alien",
		rarity = "Mythic",
		tipMultiplier = 50, -- overridden by Economy.golden.tipMultiplier at runtime
		color = Color3.fromRGB(255, 215, 0),
		icon = "🏆",
		special = true,
	},
	{
		id = "FoodCritic",
		displayName = "Gourmand Zorg (Food Critic)",
		rarity = "Legendary",
		tipMultiplier = 1,
		color = Color3.fromRGB(60, 60, 60),
		icon = "🧐",
		special = true,
	},
}

Customers.list = list
Customers.byId = {} :: { [string]: Species }
for _, species in list do
	Customers.byId[species.id] = species
end

return Customers
