--!strict
-- Scales a ScreenGui down on small screens (phones) so layouts designed for
-- ~900px tall viewports stay readable.

local Scale = {}

local DESIGN_HEIGHT = 900
local MIN_SCALE = 0.6
local MAX_SCALE = 1.15

function Scale.attach(screen: ScreenGui)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = screen
	local function update()
		local camera = workspace.CurrentCamera
		if camera then
			uiScale.Scale = math.clamp(camera.ViewportSize.Y / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
		end
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
end

return Scale
