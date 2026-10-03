--!strict
-- Shared type definitions. Pure types only, no runtime logic.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Cosmic"
export type StaffRole = "Barista" | "Waiter" | "Manager" | "Director"

export type StaffItem = {
	id: string,
	role: string,
	rarity: string,
	-- WorldId the staff member works in, "Global" for Directors, nil when benched.
	assigned: string?,
}

export type WorldSave = {
	unlocked: boolean,
	dishes: { [string]: number }, -- dishId -> level (0 = not bought)
}

export type Profile = {
	version: number,
	money: number,
	runEarnings: number, -- earned during the current franchise run
	lifetimeEarnings: number, -- earned across every run (drives Star Chefs)
	starChefs: number, -- unspent Star Chefs (franchise tree currency)
	totalStarChefs: number, -- every Star Chef ever earned (drives the income bonus)
	franchiseCount: number,
	franchiseNodes: { [string]: boolean },
	currentWorld: string,
	worlds: { [string]: WorldSave },
	-- Tycoon buildables owned this run: worldId -> buildId -> kind ("Station", "Table"...)
	builds: { [string]: { [string]: string } },
	tutorial: {
		step: number, -- index into Config/Tutorial.steps
		done: boolean,
	},
	staff: {
		nextId: number,
		items: { [string]: StaffItem },
	},
	codex: {
		species: { [string]: number }, -- speciesId -> times served
		recipes: { [string]: boolean },
	},
	daily: {
		streak: number,
		lastClaimDay: number,
		criticDay: number, -- day index the Food Critic was last served
	},
	offline: {
		lastOnline: number,
	},
	settings: {
		autoBuy: boolean,
	},
	stats: {
		served: number,
		goldenServed: number,
		playSeconds: number,
		bestStreak: number,
		cashCollected: number, -- cash stacks picked up (by hand or by staff)
	},
}

-- Things that change multipliers but do not live in the save (game passes, live events).
export type Context = {
	doubleMoney: boolean,
	autoServePass: boolean,
	offlinePass: boolean,
	weather: string?, -- active weather in the world being evaluated
}

export type NextUnlock = {
	kind: "Dish" | "World" | "Milestone" | "Franchise" | "None",
	id: string,
	label: string,
	cost: number,
	progress: number, -- 0..1
}

return {}
