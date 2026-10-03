--!strict
-- Colors, fonts and sizes for every screen.

local Theme = {}

Theme.colors = {
	background = Color3.fromRGB(22, 18, 40),
	panel = Color3.fromRGB(36, 30, 64),
	panelLight = Color3.fromRGB(54, 46, 92),
	panelDark = Color3.fromRGB(28, 23, 50),
	accent = Color3.fromRGB(255, 176, 66),
	accentDark = Color3.fromRGB(196, 120, 30),
	cyan = Color3.fromRGB(110, 220, 255),
	good = Color3.fromRGB(96, 214, 120),
	goodDark = Color3.fromRGB(52, 150, 76),
	bad = Color3.fromRGB(240, 92, 92),
	locked = Color3.fromRGB(90, 86, 110),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(186, 180, 214),
	gold = Color3.fromRGB(255, 215, 0),
	star = Color3.fromRGB(255, 226, 110),
	pink = Color3.fromRGB(255, 120, 200),
	outline = Color3.fromRGB(30, 20, 45), -- thick cartoon outlines
}

Theme.fonts = {
	title = Enum.Font.FredokaOne,
	body = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

Theme.corner = UDim.new(0, 12)
Theme.smallCorner = UDim.new(0, 8)
Theme.padding = 10

return Theme
