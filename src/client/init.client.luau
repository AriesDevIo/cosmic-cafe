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
	"WorldsController",
	"CodexController",
	"DailyController",
	"FranchiseController",
	"StoreController",
	"WorldObjectsController",
	"BuildFxController",
	"TutorialController",
	-- StateController last: it fires Ready, so every listener must be connected.
	"StateController",
}

for _, name in order do
	-- One broken controller must not stop the rest (StateController sends Ready).
	local ok, err = pcall(function()
		local controller = require(Controllers:WaitForChild(name)) :: any
		(controller :: Controller).start()
		return nil
	end)
	if not ok then
		warn("[CosmicCafe] " .. name .. " failed to start: " .. tostring(err))
	end
end
