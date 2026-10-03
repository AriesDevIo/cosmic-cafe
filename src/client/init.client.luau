--!strict
-- Client entry point: starts every controller in order.

local Controllers = script:WaitForChild("Controllers")

type Controller = { start: () -> () }

local order = {
	"EffectsController",
	"HUDController",
	"PopupController",
	"ShopController",
	"StaffController",
	"WorldObjectsController",
	-- StateController last: it fires Ready, so every listener must be connected.
	"StateController",
}

for _, name in order do
	local controller = require(Controllers:WaitForChild(name)) :: any
	(controller :: Controller).start()
end
