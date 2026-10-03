--!strict
-- World mechanics. Each world's `mechanic` id (Config/Worlds.luau) selects a
-- module here; CafeService asks it how customers order and how much they tip.
-- A mechanic only overrides what it changes; everything else is Basic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

export type Mechanic = {
	-- Relative weight for a customer ordering `dishId` (before the ready-tray bias).
	orderWeight: (dishId: string, ctx: Types.Context) -> number,
	-- Extra tip multiplier when `servedDish` is handed to a customer who ordered `orderedDish`.
	serveMultiplier: (orderedDish: string, servedDish: string) -> number,
}

local Mechanics = {}

local modules: { [string]: Mechanic } = {
	Basic = require(script.Basic),
	Weather = require(script.Weather),
	FishOrders = require(script.FishOrders),
	-- Not implemented yet (worlds 4-5 are config stubs): play like Basic.
	Conveyor = require(script.Basic),
	TimeDilation = require(script.Basic),
}

function Mechanics.get(mechanicId: string): Mechanic
	return modules[mechanicId] or modules.Basic
end

return Mechanics
