--!strict
-- Client-side rendering of map objects from server attributes:
--   * billboards on your stations (level, cook progress, ready servings)
--   * order bubbles + patience bars on your customers
--   * other players' prompts are hidden so you only interact with your cafe
--   * UnlockGates of worlds you own become passable (locally)
--   * "<name>'s Cafe" signs over owned plots

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Customers = require(Shared.Config.Customers)
local Dishes = require(Shared.Config.Dishes)
local Economy = require(Shared.Config.Economy)
local Map = require(Shared.Config.Map)

local Builder = require(script.Parent.Parent.UI.Builder)
local Theme = require(script.Parent.Parent.UI.Theme)
local StateController = require(script.Parent.StateController)

local WorldObjectsController = {}

local player = Players.LocalPlayer
local OWNER = Map.attributes.Owner

type StationView = { part: BasePart, gui: BillboardGui, title: TextLabel, status: TextLabel, fill: Frame }
type CustomerView = { model: Model, gui: BillboardGui, order: TextLabel, fill: Frame }

local stationViews: { [BasePart]: StationView } = {}
local customerViews: { [Model]: CustomerView } = {}
local prompts: { [ProximityPrompt]: number } = {} -- prompt -> original distance
local plotSigns: { [Instance]: BillboardGui } = {}

local function isMine(instance: Instance): boolean
	return instance:GetAttribute(OWNER) == player.UserId
end

-- Stations ----------------------------------------------------------------------------

local function makeStationView(part: BasePart): StationView
	local gui = Builder.new("BillboardGui", {
		Name = "StationView",
		Size = UDim2.fromOffset(170, 74),
		StudsOffset = Vector3.new(0, part.Size.Y / 2 + 4.5, 0),
		MaxDistance = 90,
		LightInfluence = 0,
		Adornee = part,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local panel = Builder.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, { Builder.corner(), Builder.stroke(Theme.colors.accent, 2) })
	local title = Builder.label({
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 24),
		Font = Theme.fonts.title,
		MaxTextSize = 20,
		Parent = panel,
	})
	local bar, fill = Builder.bar({
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 0, 12),
		Parent = panel,
	}, Theme.colors.accent)
	bar.Name = "Progress"
	local status = Builder.label({
		Position = UDim2.fromOffset(6, 48),
		Size = UDim2.new(1, -12, 0, 20),
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.textDim,
		MaxTextSize = 15,
		Parent = panel,
	})
	return { part = part, gui = gui, title = title, status = status, fill = fill }
end

local function updateStation(view: StationView, now: number)
	local part = view.part
	local dish = Dishes.byId[part:GetAttribute("Dish") :: string]
	if dish == nil then
		return
	end
	local level = (part:GetAttribute("Level") or 0) :: number
	local ready = (part:GetAttribute("Ready") or 0) :: number
	local capacity = (part:GetAttribute("TrayCapacity") or 0) :: number
	local cooking = part:GetAttribute("Cooking") == true
	local cookEnd = (part:GetAttribute("CookEnd") or 0) :: number
	local cookTime = (part:GetAttribute("CookTime") or 1) :: number
	local auto = part:GetAttribute("Auto") == true

	view.title.Text = dish.icon .. " " .. dish.displayName .. (if level > 0 then " · Lv " .. level else "")
	if level <= 0 then
		view.fill.Size = UDim2.fromScale(0, 1)
		view.status.Text = "🔒 Unlock it in the Menu"
		return
	end
	local progress = 0
	if cooking and cookTime > 0 then
		progress = math.clamp(1 - (cookEnd - now) / cookTime, 0, 1)
		if cookTime < 0.25 then
			progress = 1 -- too fast to animate
		end
	end
	view.fill.Size = UDim2.fromScale(progress, 1)
	local hint
	if ready >= capacity and capacity > 0 then
		hint = "Tray full! Serve customers"
	elseif auto then
		hint = "🤖 Barista cooking"
	elseif cooking then
		hint = "Cooking..."
	else
		hint = "Tap to cook!"
	end
	view.status.Text = string.format("Ready %d/%d · %s", ready, capacity, hint)
	view.status.TextColor3 = if not cooking
			and not auto
			and ready < capacity
		then Theme.colors.accent
		else Theme.colors.textDim
end

-- Customers -----------------------------------------------------------------------------

local function makeCustomerView(model: Model): CustomerView?
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local species = Customers.byId[model:GetAttribute("Species") :: string]
	if species == nil then
		return nil
	end
	local rarity = Customers.rarities[species.rarity]
	local gui = Builder.new("BillboardGui", {
		Name = "CustomerView",
		Size = UDim2.fromOffset(150, 86),
		StudsOffset = Vector3.new(0, 7, 0),
		MaxDistance = 80,
		LightInfluence = 0,
		Adornee = root,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Builder.label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.fonts.bold,
		TextColor3 = if model:GetAttribute("Golden") then Theme.colors.gold else rarity.color,
		TextStrokeTransparency = 0.3,
		Text = species.displayName,
		MaxTextSize = 16,
		Parent = gui,
	})
	local bubble = Builder.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(60, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = gui,
	}, { Builder.corner(), Builder.stroke(Color3.new(0, 0, 0), 2) })
	local order = Builder.label({ Size = UDim2.fromScale(1, 1), MaxTextSize = 32, Parent = bubble })
	local _bar, fill = Builder.bar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(90, 8),
		Parent = gui,
	}, Theme.colors.good)
	return { model = model, gui = gui, order = order, fill = fill }
end

local function readyFor(dishId: string): boolean
	for part in stationViews do
		if part:GetAttribute("Dish") == dishId then
			return ((part:GetAttribute("Ready") or 0) :: number) > 0
		end
	end
	return false
end

local function updateCustomer(view: CustomerView, now: number)
	local model = view.model
	local dish = Dishes.byId[model:GetAttribute("Order") :: string]
	if dish == nil then
		return
	end
	local ready = readyFor(dish.id)
	view.order.Text = dish.icon .. (if ready then "✅" else "")
	if model:GetAttribute("Leaving") then
		view.gui.Enabled = false
		return
	end
	local patienceEnd = model:GetAttribute("PatienceEnd") :: number?
	if patienceEnd then
		local patience = if model:GetAttribute("Critic")
			then Economy.daily.criticPatience
			else Economy.cafe.customerPatience
		local left = math.clamp((patienceEnd - now) / patience, 0, 1)
		view.fill.Size = UDim2.fromScale(left, 1)
		view.fill.BackgroundColor3 = if left > 0.5
			then Theme.colors.good
			elseif left > 0.2 then Theme.colors.accent
			else Theme.colors.bad
	else
		view.fill.Size = UDim2.fromScale(1, 1)
	end
end

-- Gates / signs / prompts --------------------------------------------------------------------

local function refreshGates()
	local profile = StateController.get()
	if profile == nil then
		return
	end
	for _, gate in CollectionService:GetTagged(Map.tags.UnlockGate) do
		local worldId = gate:GetAttribute(Map.attributes.World)
		local open = type(worldId) == "string" and profile.worlds[worldId] ~= nil and profile.worlds[worldId].unlocked
		local parts: { BasePart } = {}
		if gate:IsA("BasePart") then
			table.insert(parts, gate)
		end
		for _, descendant in gate:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		for _, part in parts do
			if part:GetAttribute("OriginalTransparency") == nil then
				part:SetAttribute("OriginalTransparency", part.Transparency)
				part:SetAttribute("OriginalCollide", part.CanCollide)
			end
			part.CanCollide = if open then false else part:GetAttribute("OriginalCollide") :: boolean
			part.Transparency = if open then 0.85 else part:GetAttribute("OriginalTransparency") :: number
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not open
			end
		end
	end
end

local function ownerOf(prompt: ProximityPrompt): number?
	local current: Instance? = prompt.Parent
	while current and current ~= workspace do
		local owner = current:GetAttribute(OWNER)
		if owner ~= nil then
			return owner :: number
		end
		current = current.Parent
	end
	return nil
end

local function refreshPrompts()
	for prompt, original in prompts do
		if prompt.Parent == nil then
			prompts[prompt] = nil
			continue
		end
		local owner = ownerOf(prompt)
		prompt.MaxActivationDistance = if owner ~= nil and owner ~= player.UserId then 0 else original
	end
end

local function trackPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and prompts[instance] == nil then
		prompts[instance] = instance.MaxActivationDistance
	end
end

local function refreshSigns()
	for _, plot in CollectionService:GetTagged(Map.tags.CafePlot) do
		local name = plot:GetAttribute("OwnerName")
		local sign: BillboardGui? = plotSigns[plot]
		if name == nil then
			if sign then
				sign:Destroy()
				plotSigns[plot] = nil
			end
			continue
		end
		if sign == nil then
			local adornee = if plot:IsA("BasePart") then plot elseif plot:IsA("Model") then plot.PrimaryPart else nil
			if adornee == nil then
				continue
			end
			local created: BillboardGui = Builder.new("BillboardGui", {
				Size = UDim2.fromOffset(260, 40),
				StudsOffset = Vector3.new(0, 18, 0),
				MaxDistance = 200,
				LightInfluence = 0,
				Adornee = adornee,
				Parent = player:WaitForChild("PlayerGui"),
			})
			Builder.label({
				Size = UDim2.fromScale(1, 1),
				Font = Theme.fonts.title,
				TextStrokeTransparency = 0.2,
				MaxTextSize = 30,
				Parent = created,
			})
			plotSigns[plot] = created
			sign = created
		end
		local label = (sign :: BillboardGui):FindFirstChildOfClass("TextLabel") :: TextLabel
		label.Text = name .. "'s Cafe"
		label.TextColor3 = if isMine(plot) then Theme.colors.gold else Theme.colors.text
	end
end

-- Loop -----------------------------------------------------------------------------------------

local function scan()
	for _, part in CollectionService:GetTagged(Map.tags.Station) do
		if part:IsA("BasePart") and isMine(part) and stationViews[part] == nil then
			stationViews[part] = makeStationView(part)
		end
	end
	for part, view in stationViews do
		if part.Parent == nil or not isMine(part) then
			view.gui:Destroy()
			stationViews[part] = nil
		end
	end
	for _, model in CollectionService:GetTagged(Map.tags.Customer) do
		if model:IsA("Model") and isMine(model) and customerViews[model] == nil then
			local view = makeCustomerView(model)
			if view then
				customerViews[model] = view
			end
		end
	end
	for model, view in customerViews do
		if model.Parent == nil then
			view.gui:Destroy()
			customerViews[model] = nil
		end
	end
end

function WorldObjectsController.start()
	for _, descendant in workspace:GetDescendants() do
		trackPrompt(descendant)
	end
	workspace.DescendantAdded:Connect(trackPrompt)

	StateController.changed:connect(refreshGates)

	local sinceScan = 0
	RunService.RenderStepped:Connect(function(dt)
		sinceScan += dt
		if sinceScan >= 0.5 then
			sinceScan = 0
			scan()
			refreshPrompts()
			refreshSigns()
		end
		local now = workspace:GetServerTimeNow()
		for _, view in stationViews do
			updateStation(view, now)
		end
		for _, view in customerViews do
			updateCustomer(view, now)
		end
	end)
end

return WorldObjectsController
