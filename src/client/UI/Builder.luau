--!strict
-- Tiny declarative helpers for building UI in code.
--   Builder.new("Frame", { Size = ..., Parent = ... }, { children })

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Builder = {}

function Builder.new(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Builder.corner(radius: UDim?): Instance
	return Builder.new("UICorner", { CornerRadius = radius or Theme.corner })
end

function Builder.stroke(color: Color3?, thickness: number?): Instance
	return Builder.new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 0.3,
	})
end

function Builder.padding(pixels: number?): Instance
	local p = UDim.new(0, pixels or Theme.padding)
	return Builder.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function Builder.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): Instance
	return Builder.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

function Builder.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		TextColor3 = Theme.colors.text,
		TextScaled = true,
		Text = "",
	}
	for key, value in props do
		if key ~= "MaxTextSize" then -- belongs to the UITextSizeConstraint below
			defaults[key] = value
		end
	end
	local label = Builder.new("TextLabel", defaults)
	Builder.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 28, Parent = label })
	return label
end

-- A rounded button. `onClick` runs on Activated.
function Builder.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.colors.accent,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
		TextScaled = true,
		AutoButtonColor = true,
		Text = "",
	}
	for key, value in props do
		if key ~= "MaxTextSize" then
			defaults[key] = value
		end
	end
	local button = Builder.new("TextButton", defaults, {
		Builder.corner(Theme.smallCorner),
		Builder.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 22 }),
		Builder.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	local bounce = Instance.new("UIScale")
	bounce.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(bounce, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(bounce, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		bounce.Scale = 1
	end)
	button.Activated:Connect(onClick)
	return button
end

-- A horizontal progress bar; returns (frame, fill).
function Builder.bar(props: { [string]: any }, fillColor: Color3): (Frame, Frame)
	local defaults: { [string]: any } = { BackgroundColor3 = Theme.colors.panelDark, BorderSizePixel = 0 }
	for key, value in props do
		defaults[key] = value
	end
	local frame = Builder.new("Frame", defaults, { Builder.corner(UDim.new(1, 0)) })
	local fill = Builder.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	}, { Builder.corner(UDim.new(1, 0)) })
	return frame, fill
end

return Builder
