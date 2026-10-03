--!strict
-- Customer looks. Customers are R15 avatars built with
-- Players:CreateHumanoidModelFromDescription from these presets.
--
-- Asset ids (hair accessories, classic shirts/pants, faces) are 0 = "none"
-- placeholders: paste catalog ids into the lists below to dress customers up.
-- Body colors alone already give every preset a distinct "outfit" (torso/arm
-- color reads as the shirt, leg color as the pants), so the game looks fine
-- before any ids are filled in. If an asset fails to load the customer falls
-- back to plain body colors.

export type Preset = {
	name: string,
	skin: Color3,
	shirtColor: Color3, -- torso + upper arms
	pantsColor: Color3, -- legs
	hair: string, -- comma-separated accessory ids ("" = none)
	shirt: number, -- classic shirt id (0 = none)
	pants: number, -- classic pants id (0 = none)
	face: number, -- face id (0 = default smile)
	height: number, -- HeightScale
	width: number, -- WidthScale
}

local Outfits = {}

Outfits.skinTones = {
	Color3.fromRGB(255, 224, 189),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(92, 58, 30),
	Color3.fromRGB(255, 205, 170),
	Color3.fromRGB(234, 192, 134),
}

Outfits.shirtColors = {
	Color3.fromRGB(230, 70, 70),
	Color3.fromRGB(70, 140, 230),
	Color3.fromRGB(90, 200, 120),
	Color3.fromRGB(250, 200, 60),
	Color3.fromRGB(170, 100, 220),
	Color3.fromRGB(255, 140, 60),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(40, 40, 50),
	Color3.fromRGB(255, 130, 190),
	Color3.fromRGB(60, 200, 210),
}

Outfits.pantsColors = {
	Color3.fromRGB(40, 60, 120),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(120, 90, 60),
	Color3.fromRGB(80, 80, 90),
	Color3.fromRGB(200, 180, 140),
	Color3.fromRGB(60, 100, 60),
}

-- Paste catalog asset ids here (0 = none). Each preset picks one by index.
Outfits.hairAccessories = { "", "", "", "" } -- e.g. "123456789" or "111,222"
Outfits.shirts = { 0, 0, 0, 0 }
Outfits.pants = { 0, 0, 0, 0 }
Outfits.faces = { 0, 0, 0, 0 }

local function pick<T>(list: { T }, index: number): T
	return list[(index - 1) % #list + 1]
end

-- 32 presets: every skin tone with several shirt/pants color combos.
local presets: { Preset } = {}
for i = 1, 32 do
	table.insert(presets, {
		name = "Customer" .. i,
		skin = pick(Outfits.skinTones, i),
		shirtColor = pick(Outfits.shirtColors, i * 3 + 1),
		pantsColor = pick(Outfits.pantsColors, i * 5 + 2),
		hair = pick(Outfits.hairAccessories, i),
		shirt = pick(Outfits.shirts, i + 1),
		pants = pick(Outfits.pants, i + 2),
		face = pick(Outfits.faces, i + 3),
		height = 0.92 + (i % 5) * 0.04,
		width = 0.9 + (i % 4) * 0.05,
	})
end
Outfits.presets = presets

-- The daily Food Critic: a sharp black suit.
Outfits.critic = {
	name = "FoodCritic",
	skin = Color3.fromRGB(224, 172, 105),
	shirtColor = Color3.fromRGB(25, 25, 30),
	pantsColor = Color3.fromRGB(25, 25, 30),
	hair = "",
	shirt = 0,
	pants = 0,
	face = 0,
	height = 1.05,
	width = 0.95,
} :: Preset

-- Default R15 animations (Roblox's stock Animate script ids).
Outfits.animations = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	sit = "rbxassetid://2506281703",
} :: { [string]: string }

-- How many avatar templates are built ahead of time at server start.
Outfits.prewarmCount = 12

return Outfits
