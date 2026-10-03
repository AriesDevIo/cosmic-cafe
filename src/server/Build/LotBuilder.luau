--!strict
-- Creates the "Buildables" folder for a generated lot from Config/Buildables,
-- using exactly the attribute contract a hand-built map uses
-- (docs/MAP_CONTRACT.md), so BuildService treats both the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buildables = require(ReplicatedStorage:WaitForChild("Shared").Config.Buildables)

local LotBuilder = {}

local function makePart(spec: Buildables.PartSpec, surface: CFrame): BasePart
	local part: BasePart = if spec.seat then Instance.new("Seat") else Instance.new("Part")
	part.Name = spec.name
	part.Anchored = true
	part.Size = spec.size
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	part.CanCollide = if spec.collide == nil then true else spec.collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local cframe = surface * CFrame.new(spec.offset)
	if spec.shape then
		(part :: Part).Shape = spec.shape
		if spec.shape == Enum.PartType.Cylinder then
			cframe *= Buildables.uprightCylinder
		end
	end
	part.CFrame = cframe
	return part
end

-- Builds every buildable of `worldId` under a new Folder "Buildables" in `parent`.
function LotBuilder.build(worldId: string, surface: CFrame, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Buildables"
	local defs, templates = Buildables.forWorld(worldId)
	for _, def in defs do
		local template = templates[def.id]
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("BuildId", def.id)
		model:SetAttribute("DisplayName", def.displayName)
		model:SetAttribute("Cost", def.cost)
		model:SetAttribute("Order", def.order)
		model:SetAttribute("Requires", table.concat(def.requires, ","))
		model:SetAttribute("Kind", def.kind)
		if def.dish then
			model:SetAttribute("Dish", def.dish)
		end
		for index, spec in template.parts do
			local part = makePart(spec, surface)
			part.Parent = model
			if index == 1 then
				model.PrimaryPart = part
			end
		end
		local pad = Instance.new("Part")
		pad.Name = "PadSpot"
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanQuery = false
		pad.Transparency = 1
		pad.Size = Vector3.new(1, 0.2, 1)
		pad.CFrame = surface * CFrame.new(template.pad)
		pad.Parent = model
		model.Parent = folder
	end
	folder.Parent = parent
	return folder
end

return LotBuilder
