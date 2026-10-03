--!strict
-- Modal windows (one open at a time). Controllers create a window once and
-- re-render its body whenever the state changes while it's open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)
local Builder = require(script.Parent.Builder)
local Theme = require(script.Parent.Theme)

export type Window = {
	id: string,
	frame: Frame,
	body: ScrollingFrame,
	title: TextLabel,
	render: (() -> ())?,
}

local Window = {}

Window.opened = Signal.new() :: Signal.Signal<string>
Window.closed = Signal.new() :: Signal.Signal<string>

local windows: { [string]: Window } = {}
local current: string? = nil
local screen: ScreenGui? = nil

local function getScreen(): ScreenGui
	if screen == nil then
		local player = Players.LocalPlayer
		screen = Builder.new("ScreenGui", {
			Name = "CosmicCafeWindows",
			ResetOnSpawn = false,
			DisplayOrder = 5,
			IgnoreGuiInset = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
	end
	return screen :: ScreenGui
end

function Window.create(id: string, title: string): Window
	local frame = Builder.new("Frame", {
		Name = id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.74),
		BackgroundColor3 = Theme.colors.panel,
		Visible = false,
		Parent = getScreen(),
	}, {
		Builder.corner(),
		Builder.stroke(Theme.colors.accent, 3),
		Builder.new("UISizeConstraint", { MaxSize = Vector2.new(760, 620), MinSize = Vector2.new(300, 260) }),
	})
	local header = Builder.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = Theme.colors.panelLight,
		Parent = frame,
	}, { Builder.corner() })
	local titleLabel = Builder.label({
		Name = "Title",
		Text = title,
		Font = Theme.fonts.title,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -80, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		Parent = header,
	})
	Builder.button({
		Name = "Close",
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Theme.colors.bad,
		Parent = header,
	}, function()
		Window.close(id)
	end)
	local body = Builder.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, {
		Builder.list(nil, 8),
		Builder.new("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 12),
		}),
	})
	local window: Window = { id = id, frame = frame, body = body, title = titleLabel, render = nil }
	windows[id] = window
	return window
end

-- Removes everything from a window body except its layout objects.
function Window.clear(window: Window)
	for _, child in window.body:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function Window.isOpen(id: string): boolean
	return current == id
end

function Window.open(id: string)
	if current and current ~= id then
		Window.close(current)
	end
	local window = windows[id]
	if window == nil then
		return
	end
	current = id
	window.frame.Visible = true
	if window.render then
		window.render()
	end
	Window.opened:fire(id)
end

function Window.close(id: string)
	local window = windows[id]
	if window == nil then
		return
	end
	window.frame.Visible = false
	if current == id then
		current = nil
	end
	Window.closed:fire(id)
end

function Window.toggle(id: string)
	if current == id then
		Window.close(id)
	else
		Window.open(id)
	end
end

-- Re-renders the open window (called on state changes).
function Window.refresh(id: string)
	local window = windows[id]
	if window and current == id and window.render then
		window.render()
	end
end

return Window
