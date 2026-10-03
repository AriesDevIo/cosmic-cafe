--!strict
-- Staff window: crew slots for the current world (hire / see who works there),
-- crates, and the staff room (select to assign, bench or fuse 3 duplicates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.Util.BigNum)
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Staff = require(Shared.Config.Staff)
local Stats = require(Shared.Util.Stats)
local Worlds = require(Shared.Config.Worlds)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local Window = require(script.Parent.Parent.UI.Window)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local StateController = require(script.Parent.StateController)

local StaffController = {}

local window: Window.Window
local selected: { string } = {}

local function section(text: string, order: number)
	Builder.label({
		LayoutOrder = order,
		Text = text,
		Font = Theme.fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		MaxTextSize = 24,
		Parent = window.body,
	})
end

local function isSelected(id: string): boolean
	return table.find(selected, id) ~= nil
end

local function toggleSelect(id: string)
	local index = table.find(selected, id)
	if index then
		table.remove(selected, index)
	else
		if #selected >= Staff.fuseCount then
			table.remove(selected, 1)
		end
		table.insert(selected, id)
	end
	EffectsController.play("Click")
end

local function roleEffect(roleId: string, rarity: string): string
	local multiplier = Stats.rarityMultiplier(rarity)
	if roleId == "Barista" then
		return string.format("x%g cook speed", multiplier)
	elseif roleId == "Waiter" then
		return string.format("x%g serve speed", multiplier)
	elseif roleId == "Manager" then
		return "background income"
	end
	return "offline from all worlds"
end

local function slotCard(profile: any, worldId: string, roleId: string, order: number, parent: Instance)
	local role = Staff.roles[roleId]
	local item = Stats.assignedStaff(profile, worldId, roleId)
	local card = Builder.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(160, 120),
		BackgroundColor3 = Theme.colors.panelLight,
		Parent = parent,
	}, { Builder.corner() })
	Builder.label({
		Text = role.icon .. " " .. role.displayName,
		Font = Theme.fonts.bold,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 22),
		MaxTextSize = 17,
		Parent = card,
	})
	if item then
		local rarity = Staff.rarities[item.rarity]
		Builder.stroke(rarity.color, 3).Parent = card
		Builder.label({
			Text = item.rarity,
			TextColor3 = rarity.color,
			Font = Theme.fonts.title,
			Position = UDim2.fromOffset(6, 34),
			Size = UDim2.new(1, -12, 0, 30),
			MaxTextSize = 24,
			Parent = card,
		})
		Builder.label({
			Text = roleEffect(roleId, item.rarity),
			TextColor3 = Theme.colors.textDim,
			Position = UDim2.fromOffset(6, 70),
			Size = UDim2.new(1, -12, 0, 36),
			MaxTextSize = 15,
			TextWrapped = true,
			Parent = card,
		})
		return
	end
	if not Progression.canHireRole(profile, roleId) then
		Builder.label({
			Text = "🔒 Unlocks in " .. Worlds.list[role.unlockWorldIndex].displayName,
			TextColor3 = Theme.colors.textDim,
			Position = UDim2.fromOffset(6, 40),
			Size = UDim2.new(1, -12, 0, 60),
			TextWrapped = true,
			MaxTextSize = 15,
			Parent = card,
		})
		return
	end
	local cost = Stats.hireCost(worldId, roleId)
	Builder.label({
		Text = role.description,
		TextColor3 = Theme.colors.textDim,
		Position = UDim2.fromOffset(6, 28),
		Size = UDim2.new(1, -12, 0, 44),
		TextWrapped = true,
		MaxTextSize = 12,
		Parent = card,
	})
	Builder.button({
		Text = "Hire " .. BigNum.money(cost),
		Position = UDim2.new(0, 8, 1, -42),
		Size = UDim2.new(1, -16, 0, 34),
		BackgroundColor3 = if cost <= profile.money then Theme.colors.good else Theme.colors.locked,
		MaxTextSize = 17,
		Parent = card,
	}, function()
		EffectsController.play("Buy")
		Net.event("Hire"):FireServer(worldId, roleId)
	end)
end

local function staffCard(item: any, order: number, parent: Instance)
	local role = Staff.roles[item.role]
	local rarity = Staff.rarities[item.rarity]
	local chosen = isSelected(item.id)
	local where = if item.assigned == nil
		then "Benched"
		elseif item.assigned == "Global" then "Head office"
		else Worlds.byId[item.assigned].displayName
	local card = Builder.button({
		LayoutOrder = order,
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = if chosen then Theme.colors.accentDark else Theme.colors.panelLight,
		Parent = parent,
	}, function()
		toggleSelect(item.id)
		Window.refresh("Staff")
	end)
	Builder.stroke(rarity.color, if chosen then 4 else 2).Parent = card
	Builder.label({ Text = role.icon, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 40), Parent = card })
	Builder.label({
		Text = item.rarity,
		TextColor3 = rarity.color,
		Font = Theme.fonts.bold,
		Position = UDim2.fromOffset(4, 46),
		Size = UDim2.new(1, -8, 0, 20),
		MaxTextSize = 16,
		Parent = card,
	})
	Builder.label({
		Text = role.displayName,
		Position = UDim2.fromOffset(4, 66),
		Size = UDim2.new(1, -8, 0, 18),
		MaxTextSize = 13,
		Parent = card,
	})
	Builder.label({
		Text = where,
		TextColor3 = Theme.colors.textDim,
		Position = UDim2.fromOffset(4, 86),
		Size = UDim2.new(1, -8, 0, 16),
		MaxTextSize = 12,
		Parent = card,
	})
end

local function row(order: number, height: number): Frame
	return Builder.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = window.body,
	}, {
		Builder.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(height, height),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function render()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	Window.clear(window)
	-- forget selections of staff that no longer exist
	for i = #selected, 1, -1 do
		if profile.staff.items[selected[i]] == nil then
			table.remove(selected, i)
		end
	end
	local worldId = profile.currentWorld
	local world = Worlds.byId[worldId]

	section("Crew in " .. world.displayName, 1)
	local slots = Builder.new("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		Parent = window.body,
	}, { Builder.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	for index, roleId in Staff.roleOrder do
		slotCard(profile, worldId, roleId, index, slots)
	end

	section("Crates", 3)
	local crates = Builder.new("Frame", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = window.body,
	}, { Builder.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	for index, crateId in Staff.crateOrder do
		local crate = Staff.crates[crateId]
		local cost = Stats.crateCost(profile, crateId)
		Builder.button({
			LayoutOrder = index,
			Text = "📦 " .. crate.displayName .. "\n" .. BigNum.money(cost),
			Size = UDim2.fromOffset(200, 54),
			BackgroundColor3 = if cost <= profile.money then Theme.colors.accent else Theme.colors.locked,
			MaxTextSize = 17,
			Parent = crates,
		}, function()
			EffectsController.play("Buy")
			Net.event("OpenCrate"):FireServer(crateId)
		end)
	end

	local items = {}
	for _, item in profile.staff.items do
		table.insert(items, item)
	end
	table.sort(items, function(a, b)
		if a.role ~= b.role then
			return (table.find(Staff.roleOrder, a.role) or 0) < (table.find(Staff.roleOrder, b.role) or 0)
		end
		local ra = table.find(Staff.rarityOrder, a.rarity) or 0
		local rb = table.find(Staff.rarityOrder, b.rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)

	section(string.format("Staff room (%d/%d)", #items, Staff.maxInventory), 5)
	local actions = Builder.new("Frame", {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = window.body,
	}, { Builder.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	local single = if #selected == 1 then profile.staff.items[selected[1]] else nil
	Builder.button({
		LayoutOrder = 1,
		Text = "Assign to " .. world.displayName,
		Size = UDim2.fromOffset(210, 36),
		BackgroundColor3 = if single then Theme.colors.good else Theme.colors.locked,
		Parent = actions,
	}, function()
		if single then
			Net.event("Assign"):FireServer(single.id, worldId)
			table.clear(selected)
		end
	end)
	Builder.button({
		LayoutOrder = 2,
		Text = "Bench",
		Size = UDim2.fromOffset(100, 36),
		BackgroundColor3 = if single and single.assigned then Theme.colors.panelLight else Theme.colors.locked,
		Parent = actions,
	}, function()
		if single then
			Net.event("Assign"):FireServer(single.id, nil)
			table.clear(selected)
		end
	end)
	Builder.button({
		LayoutOrder = 3,
		Text = string.format("✨ Fuse (%d/%d)", #selected, Staff.fuseCount),
		Size = UDim2.fromOffset(150, 36),
		BackgroundColor3 = if #selected == Staff.fuseCount then Theme.colors.accent else Theme.colors.locked,
		Parent = actions,
	}, function()
		if #selected == Staff.fuseCount then
			Net.event("Fuse"):FireServer(table.clone(selected))
			table.clear(selected)
		end
	end)

	local grid = row(7, 110)
	for index, item in items do
		staffCard(item, index, grid)
	end
	if #items == 0 then
		Builder.label({
			LayoutOrder = 8,
			Text = "No staff yet. Hire a Barista to cook for you!",
			TextColor3 = Theme.colors.textDim,
			Size = UDim2.new(1, 0, 0, 24),
			MaxTextSize = 18,
			Parent = window.body,
		})
	end
end

-- "!" on the Staff button while an empty slot in this world is affordable.
local function refreshBadge()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	local affordable = false
	for _, roleId in Staff.roleOrder do
		if
			Progression.canHireRole(profile, roleId)
			and Stats.assignedStaff(profile, profile.currentWorld, roleId) == nil
			and Stats.hireCost(profile.currentWorld, roleId) <= profile.money
		then
			affordable = true
		end
	end
	HUDController.setBadge("Staff", affordable)
end

function StaffController.start()
	window = Window.create("Staff", "🧑‍🍳 Staff")
	window.render = render
	StateController.changed:connect(function()
		Window.refresh("Staff")
		refreshBadge()
	end)
	StateController.moneyChanged:connect(refreshBadge)
end

return StaffController
