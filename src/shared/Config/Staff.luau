--!strict
-- Staff roles, rarities, hiring, crates and fusing.

export type Role = {
	id: string,
	displayName: string,
	icon: string,
	description: string,
	global: boolean, -- true = one slot for the whole account instead of one per world
	hireCost: number, -- multiplied by the world's priceScale
	unlockWorldIndex: number, -- can be hired once this world index is unlocked
}

export type Rarity = {
	id: string,
	multiplier: number, -- speed / efficiency multiplier the staff member gives
	color: Color3,
}

export type Crate = {
	id: string,
	displayName: string,
	cost: number, -- multiplied by the highest unlocked world's priceScale
	odds: { [string]: number }, -- rarity id -> weight
}

local Staff = {}

Staff.roleOrder = { "Barista", "Waiter", "Manager", "Director" }

Staff.roles = {
	Barista = {
		id = "Barista",
		displayName = "Barista",
		icon = "🧑‍🍳",
		description = "Auto-cooks every station in their world. Rarity speeds up cooking.",
		global = false,
		hireCost = 250,
		unlockWorldIndex = 1,
	},
	Waiter = {
		id = "Waiter",
		displayName = "Waiter",
		icon = "🤵",
		description = "Auto-serves customers in their world. Rarity speeds up serving.",
		global = false,
		hireCost = 2500,
		unlockWorldIndex = 1,
	},
	Manager = {
		id = "Manager",
		displayName = "World Manager",
		icon = "📋",
		description = "Keeps their world earning while you are in another world.",
		global = false,
		hireCost = 2.5e5,
		unlockWorldIndex = 1,
	},
	Director = {
		id = "Director",
		displayName = "Regional Director",
		icon = "🌐",
		description = "Collects offline earnings from every automated world, not just the last one.",
		global = true,
		hireCost = 5e8,
		unlockWorldIndex = 2,
	},
} :: { [string]: Role }

Staff.rarityOrder = { "Common", "Rare", "Epic", "Legendary", "Cosmic" }

Staff.rarities = {
	Common = { id = "Common", multiplier = 1, color = Color3.fromRGB(200, 200, 200) },
	Rare = { id = "Rare", multiplier = 1.5, color = Color3.fromRGB(90, 160, 255) },
	Epic = { id = "Epic", multiplier = 2.25, color = Color3.fromRGB(190, 100, 255) },
	Legendary = { id = "Legendary", multiplier = 3.5, color = Color3.fromRGB(255, 190, 40) },
	Cosmic = { id = "Cosmic", multiplier = 6, color = Color3.fromRGB(80, 255, 230) },
} :: { [string]: Rarity }

-- Fusing `fuseCount` staff of the same role and rarity yields one of the next rarity.
Staff.fuseCount = 3

Staff.crateOrder = { "Basic", "Stellar" }

Staff.crates = {
	Basic = {
		id = "Basic",
		displayName = "Basic Crate",
		cost = 2500,
		odds = { Common = 80, Rare = 17, Epic = 3 },
	},
	Stellar = {
		id = "Stellar",
		displayName = "Stellar Crate",
		cost = 25000,
		odds = { Rare = 70, Epic = 24, Legendary = 5.5, Cosmic = 0.5 },
	},
} :: { [string]: Crate }

-- Role weights for crate rolls (Directors are hire-only).
Staff.crateRoleWeights = { Barista = 45, Waiter = 45, Manager = 10 } :: { [string]: number }

Staff.maxInventory = 60

return Staff
