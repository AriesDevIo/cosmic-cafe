--!strict
-- Guided first minutes. Each step completes when its condition is true (see
-- Util/Tutorial.luau); the client shows one big banner, a beam from the player
-- to the target and a pulsing highlight on it.

export type Step = {
	id: string,
	title: string,
	detail: string,
	-- What the beam points at: a buy pad (matching kind / dish slot), a
	-- customer, a cash stack, a station, or a HUD menu button.
	target: "Pad" | "Customer" | "Cash" | "Menu" | "None",
	padKind: string?,
	padDishSlot: number?, -- Station pads: index into the world's dishes
	menu: string?,
}

local Tutorial = {}

Tutorial.steps = {
	{
		id = "BuildFirstStation",
		title = "Build your Coffee Cart",
		detail = "Step on the glowing pad. It's FREE!",
		target = "Pad",
		padKind = "Station",
		padDishSlot = 1,
	},
	{
		id = "ServeFirst",
		title = "Serve your first customer",
		detail = "Tap Cook at the cart, then tap the customer to serve.",
		target = "Customer",
	},
	{
		id = "CollectCash",
		title = "Collect your cash",
		detail = "Walk over the cash stack your customer left.",
		target = "Cash",
	},
	{
		id = "BuyTable",
		title = "Buy a table",
		detail = "Seated customers tip more!",
		target = "Pad",
		padKind = "Table",
	},
	{
		id = "BuySecondStation",
		title = "Buy the Donut Machine",
		detail = "More dishes, more money.",
		target = "Pad",
		padKind = "Station",
		padDishSlot = 2,
	},
	{
		id = "HireBarista",
		title = "Hire your first Barista",
		detail = "Open Staff and hire a Barista to cook for you.",
		target = "Menu",
		menu = "Staff",
	},
} :: { Step }

-- Paid when the last step completes.
Tutorial.rewardMoney = 500

-- When each HUD menu button appears. `step`: visible once the tutorial is at
-- (or past) that step index; `afterTutorial`: only once it's done.
Tutorial.menus =
	{
		Shop = { step = 3 },
		Staff = { step = 6 },
		Daily = { afterTutorial = true },
		Codex = { afterTutorial = true },
		Lab = { afterTutorial = true },
		Store = { afterTutorial = true },
		-- Worlds: after the tutorial, once lifetime earnings reach this share of World 2's price
		Worlds = { afterTutorial = true, worldsAtUnlockFraction = 0.25 },
		-- Franchise: after the tutorial, once a franchise is possible (or was done)
		Franchise = { afterTutorial = true, franchise = true },
	} :: { [string]: { step: number?, afterTutorial: boolean?, worldsAtUnlockFraction: number?, franchise: boolean? } }

return Tutorial
