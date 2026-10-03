--!strict
-- Staff: hire (fills an empty slot with a Common), crates (random role +
-- rarity), fuse 3 duplicates into the next rarity, assign/bench.
-- What staff *do* (auto-cook, auto-serve, background, offline) is computed
-- from the save by Stats and applied by CafeService / EconomyService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Progression = require(Shared.Util.Progression)
local Staff = require(Shared.Config.Staff)
local Stats = require(Shared.Util.Stats)
local Validate = require(Shared.Util.Validate)
local Worlds = require(Shared.Config.Worlds)

local CafeService = require(script.Parent.CafeService)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)

local StaffService = {}

local random = Random.new()

-- Rarities at or above this index are announced to the server.
local ANNOUNCE_FROM = table.find(Staff.rarityOrder, "Legendary") or #Staff.rarityOrder

local function changed(player: Player)
	StateService.markDirty(player)
	CafeService.refresh(player)
end

local function describe(item: { role: string, rarity: string }): string
	return item.rarity .. " " .. Staff.roles[item.role].displayName
end

local function maybeAnnounce(player: Player, item: { role: string, rarity: string })
	local index = table.find(Staff.rarityOrder, item.rarity) or 1
	if index >= ANNOUNCE_FROM then
		Net.fireAll(
			"Announce",
			string.format("%s %s got a %s!", Staff.roles[item.role].icon, player.DisplayName, describe(item)),
			"#" .. Staff.rarities[item.rarity].color:ToHex()
		)
	end
end

function StaffService.init() end

function StaffService.start()
	Net.onServerEvent("Hire", function(player, worldId, roleId)
		local profile = DataService.get(player)
		if profile == nil or not Validate.oneOf(worldId, Worlds.byId) or not Validate.oneOf(roleId, Staff.roles) then
			return
		end
		local ok, err, item = Progression.hire(profile, worldId :: string, roleId :: string)
		if not ok or item == nil then
			Net.fire(player, "Notify", err or "Can't hire", "error")
			return
		end
		local role = Staff.roles[item.role]
		Net.fire(player, "Notify", role.icon .. " Hired a " .. role.displayName .. "!", "success")
		changed(player)
	end)

	Net.onServerEvent("OpenCrate", function(player, crateId)
		local profile = DataService.get(player)
		if profile == nil or not Validate.oneOf(crateId, Staff.crates) then
			return
		end
		local cost = Stats.crateCost(profile, crateId :: string)
		local ok, err, item =
			Progression.openCrate(profile, crateId :: string, random:NextNumber(), random:NextNumber())
		if not ok or item == nil then
			Net.fire(player, "Notify", err or "Can't open that", "error")
			return
		end
		Net.fire(player, "Effect", "Crate", { role = item.role, rarity = item.rarity, cost = cost })
		Net.fire(player, "Notify", "📦 " .. describe(item) .. " joined your staff room!", "success")
		maybeAnnounce(player, item)
		changed(player)
	end)

	Net.onServerEvent("Fuse", function(player, staffIds)
		local profile = DataService.get(player)
		if profile == nil or not Validate.stringArray(staffIds, Staff.fuseCount, Validate.ID_LENGTH) then
			return
		end
		local ok, err, item = Progression.fuse(profile, staffIds :: { string })
		if not ok or item == nil then
			Net.fire(player, "Notify", err or "Can't fuse", "error")
			return
		end
		Net.fire(player, "Effect", "Fuse", { role = item.role, rarity = item.rarity })
		Net.fire(player, "Notify", "✨ Fused into a " .. describe(item) .. "!", "success")
		maybeAnnounce(player, item)
		changed(player)
	end)

	Net.onServerEvent("Assign", function(player, staffId, worldId)
		local profile = DataService.get(player)
		if profile == nil or not Validate.string(staffId, Validate.ID_LENGTH) then
			return
		end
		if worldId ~= nil and not Validate.oneOf(worldId, Worlds.byId) then
			return
		end
		local ok, err = Progression.assignStaff(profile, staffId :: string, worldId :: string?)
		if not ok then
			Net.fire(player, "Notify", err or "Can't assign", "error")
			return
		end
		changed(player)
	end)
end

return StaffService
