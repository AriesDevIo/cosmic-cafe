--!strict
-- Customer NPCs: R15 avatars from Config/Outfits presets.
--
-- CreateHumanoidModelFromDescription yields (it loads assets), so one template
-- per look is built once in the background and cloned for every customer. If
-- avatars can't be created (no asset access, e.g. some Studio setups) a simple
-- part-built "blob" is used instead and moved with tweens.
--
-- Animations are played server-side through the Humanoid's Animator (NPCs
-- don't run the stock Animate script), so they replicate to every client.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Map = require(Shared.Config.Map)
local Outfits = require(Shared.Config.Outfits)

export type Npc = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?, -- nil for blob fallbacks
	tracks: { [string]: AnimationTrack },
	playing: string?,
}

local Npc = {}

local templates: { [string]: Model } = {}
local building: { [string]: boolean } = {}
local failed = false -- avatar creation is unavailable on this server
local templateFolder: Folder

local function description(preset: Outfits.Preset, tint: Color3?): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local skin = tint or preset.skin
	desc.HeadColor = skin
	desc.LeftArmColor = tint or preset.shirtColor
	desc.RightArmColor = tint or preset.shirtColor
	desc.TorsoColor = tint or preset.shirtColor
	desc.LeftLegColor = tint or preset.pantsColor
	desc.RightLegColor = tint or preset.pantsColor
	if tint == nil then
		desc.HairAccessory = preset.hair
		desc.Shirt = preset.shirt
		desc.Pants = preset.pants
		desc.Face = preset.face
	end
	desc.HeightScale = preset.height
	desc.WidthScale = preset.width
	return desc
end

local function key(preset: Outfits.Preset, tint: Color3?): string
	return preset.name .. (if tint then tint:ToHex() else "")
end

-- Builds (yielding) the template for a look. Returns nil if avatars fail.
local function buildTemplate(preset: Outfits.Preset, tint: Color3?): Model?
	local id = key(preset, tint)
	if templates[id] then
		return templates[id]
	end
	if failed or building[id] then
		return nil
	end
	building[id] = true
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(preset, tint), Enum.HumanoidRigType.R15)
	end)
	if not ok or result == nil then
		-- retry once without any catalog assets (a bad id shouldn't cost the look)
		local plain = table.clone(preset)
		plain.hair, plain.shirt, plain.pants, plain.face = "", 0, 0, 0
		ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description(plain, tint), Enum.HumanoidRigType.R15)
		end)
	end
	building[id] = nil
	if not ok or result == nil then
		failed = true
		warn("[Npc] avatars unavailable, using simple customers: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	model.Name = preset.name
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.WalkSpeed = Economy.cafe.customerWalkSpeed
		if humanoid:FindFirstChildOfClass("Animator") == nil then
			Instance.new("Animator").Parent = humanoid
		end
	end
	model.Parent = templateFolder
	templates[id] = model
	return model
end

-- Builds a few templates ahead of time so the first customers are avatars.
function Npc.prewarm()
	templateFolder = Instance.new("Folder")
	templateFolder.Name = "CosmicCafeNpcTemplates"
	templateFolder.Parent = ServerStorage
	task.spawn(function()
		for i = 1, math.min(Outfits.prewarmCount, #Outfits.presets) do
			if failed then
				return
			end
			buildTemplate(Outfits.presets[i])
		end
	end)
end

-- Blob fallback ---------------------------------------------------------------------------

local function weld(part: BasePart, root: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = part
end

local function blob(color: Color3, golden: boolean): (Model, BasePart)
	local sizes = Map.customer
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = sizes.rootSize
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root
	local material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local function piece(name: string, size: Vector3, offset: Vector3, shape: Enum.PartType)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Size = size
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.Massless = true
		part.CFrame = root.CFrame * CFrame.new(offset)
		part.Parent = model
		weld(part, root)
	end
	local bodyY = sizes.bodySize.Y / 2 - sizes.rootSize.Y / 2
	piece("Body", sizes.bodySize, Vector3.new(0, bodyY, 0), Enum.PartType.Block)
	local headY = sizes.bodySize.Y + sizes.headSize.Y / 2 - sizes.rootSize.Y / 2
	piece("Head", sizes.headSize, Vector3.new(0, headY, 0), Enum.PartType.Ball)
	return model, root
end

-- Creating -----------------------------------------------------------------------------------

local function loadTracks(npc: Npc)
	local humanoid = npc.humanoid
	if humanoid == nil then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	for name, id in Outfits.animations do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = if name == "sit" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Core
			npc.tracks[name] = track
		end
	end
	humanoid.Running:Connect(function(speed)
		if npc.playing == "sit" then
			return
		end
		Npc.play(npc, if speed > 0.5 then "walk" else "idle")
	end)
end

function Npc.play(npc: Npc, name: string)
	if npc.playing == name then
		return
	end
	for trackName, track in npc.tracks do
		if trackName ~= name and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	local track = npc.tracks[name]
	if track then
		track:Play(0.2)
	end
	npc.playing = name
end

-- A new customer. `preset` nil picks a random look; `tint` colors the whole
-- body (VIP aliens); `golden` adds sparkles. Never yields.
function Npc.create(preset: Outfits.Preset?, tint: Color3?, golden: boolean, random: Random): Npc
	local look = preset or Outfits.presets[random:NextInteger(1, #Outfits.presets)]
	local template: Model? = templates[key(look, tint)]
	if template == nil and not failed then
		task.spawn(buildTemplate, look, tint) -- ready for the next customer
		-- use any ready template of the same tint family meanwhile
		if tint == nil then
			for i = 1, #Outfits.presets do
				local other = templates[key(Outfits.presets[i])]
				if other then
					template = other
					break
				end
			end
		end
	end

	local npc: Npc
	if template then
		local model = template:Clone()
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		model.PrimaryPart = root
		npc = {
			model = model,
			root = root,
			humanoid = model:FindFirstChildOfClass("Humanoid"),
			tracks = {},
			playing = nil,
		}
	else
		local model, root = blob(tint or look.shirtColor, golden)
		npc = { model = model, root = root, humanoid = nil, tracks = {}, playing = nil }
	end
	if golden then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Rate = Map.customer.goldenSparkleRate
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		sparkles.LightEmission = 1
		sparkles.Parent = npc.root
	end
	return npc
end

-- Call after parenting into the workspace.
function Npc.activate(npc: Npc)
	if npc.humanoid then
		pcall(function()
			npc.root:SetNetworkOwner(nil) -- the server drives NPCs
		end)
		loadTracks(npc)
		Npc.play(npc, "idle")
	end
end

-- Movement ---------------------------------------------------------------------------------

local function moveDirect(humanoid: Humanoid, position: Vector3, alive: () -> boolean): boolean
	local reached = false
	local finished = false
	local connection = humanoid.MoveToFinished:Connect(function(success)
		reached = success
		finished = true
	end)
	humanoid:MoveTo(position)
	local deadline = os.clock() + Economy.cafe.moveTimeout
	while not finished and os.clock() < deadline and alive() do
		task.wait(0.1)
	end
	connection:Disconnect()
	return reached
end

-- Walks to `position` (yields). Uses pathfinding when it can, a straight line
-- otherwise. `alive` returning false aborts.
function Npc.walkTo(npc: Npc, position: Vector3, alive: () -> boolean): boolean
	local humanoid = npc.humanoid
	if humanoid == nil then
		-- blob: tween the anchored root
		local from = npc.root.Position
		local goal = Vector3.new(position.X, from.Y, position.Z)
		local direction = goal - from
		if direction.Magnitude < 0.05 then
			return alive()
		end
		local target = CFrame.lookAt(goal, goal + direction)
		local distance = direction.Magnitude
		local duration = math.max(distance / Economy.cafe.customerWalkSpeed, 0.05)
		TweenService:Create(npc.root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = target }):Play()
		task.wait(duration)
		return alive()
	end
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(npc.root.Position, position)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		for index = 2, #waypoints do
			if not alive() then
				return false
			end
			moveDirect(humanoid, waypoints[index].Position, alive)
		end
		return alive()
	end
	return moveDirect(humanoid, position, alive)
end

-- Faces a point (no yielding).
function Npc.face(npc: Npc, point: Vector3)
	local position = npc.root.Position
	local flat = Vector3.new(point.X, position.Y, point.Z)
	if (flat - position).Magnitude < 0.05 then
		return
	end
	npc.root.CFrame = CFrame.lookAt(position, flat)
end

function Npc.sit(npc: Npc, seat: Seat)
	if npc.humanoid then
		seat:Sit(npc.humanoid)
		Npc.play(npc, "sit")
	else
		npc.root.CFrame = seat.CFrame * CFrame.new(0, 1.5, 0)
	end
end

function Npc.stand(npc: Npc)
	if npc.humanoid then
		npc.humanoid.Sit = false
		npc.playing = nil
		Npc.play(npc, "idle")
	end
end

return Npc
