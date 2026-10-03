--!strict
-- Session-locked player saves (ProfileStore-style).
--
-- Each DataStore key holds { data = Profile, meta = { session = {jobId, placeId, time}? } }.
-- Loading claims the session lock inside UpdateAsync; while another live server
-- holds it we retry, and after `loadAttempts` (or once the lock is older than
-- `lockTimeoutSeconds`, i.e. its server crashed) we steal it. Every save checks
-- that we still own the lock; if another server stole it we stop saving and
-- kick the player so two servers never write the same profile.
--
-- In Studio without API access an in-memory store is used automatically.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataTemplate = require(Shared.Config.DataTemplate)
local Economy = require(Shared.Config.Economy)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)

type Profile = Types.Profile

type Session = { jobId: string, placeId: number, time: number }
type Record = { data: any, meta: { session: Session?, saves: number?, lastSave: number? } }

type Store = {
	update: (key: string, transform: (old: Record?) -> Record?) -> (),
}

type Entry = {
	profile: Profile,
	key: string,
	saving: boolean,
	released: boolean,
}

local STORE = DataTemplate.store

local DataService = {}

DataService.loaded = Signal.new() :: Signal.Signal<Player, Profile>
-- Fired right before the final save of a leaving player (write last-second data here).
DataService.releasing = Signal.new() :: Signal.Signal<Player, Profile>

local entries: { [Player]: Entry } = {}
local store: Store
local usingMock = false

-- Stores -------------------------------------------------------------------------

local function robloxStore(): Store
	local dataStore = DataStoreService:GetDataStore(STORE.name)
	return {
		update = function(key, transform)
			dataStore:UpdateAsync(key, function(old)
				return transform(old)
			end)
		end,
	}
end

local function mockStore(): Store
	local memory: { [string]: Record } = {}
	return {
		update = function(key, transform)
			local result = transform(TableUtil.deepCopy(memory[key]))
			if result ~= nil then
				memory[key] = TableUtil.deepCopy(result)
			end
		end,
	}
end

local function chooseStore(): Store
	if RunService:IsStudio() then
		local ok = pcall(function()
			DataStoreService:GetDataStore(STORE.name):GetAsync("__probe")
		end)
		if not ok then
			usingMock = true
			warn("[DataService] DataStore API unavailable in Studio, using an in-memory store (nothing persists)")
			return mockStore()
		end
	end
	return robloxStore()
end

-- Helpers ------------------------------------------------------------------------

local function now(): number
	return os.time()
end

local function mySession(): Session
	return { jobId = game.JobId, placeId = game.PlaceId, time = now() }
end

local function isMine(session: Session?): boolean
	return session ~= nil and session.jobId == game.JobId and session.placeId == game.PlaceId
end

-- DataStores reject NaN / inf; replace them so one bad number never kills a save.
local function sanitize(value: any): any
	if type(value) == "number" then
		if value ~= value then
			return 0
		elseif value == math.huge then
			return 1e308
		elseif value == -math.huge then
			return -1e308
		end
		return value
	elseif type(value) == "table" then
		local clean = {}
		for key, child in value do
			clean[key] = sanitize(child)
		end
		return clean
	end
	return value
end

-- Upgrades old saves. Bump DataTemplate.version and add a step here when a
-- field is renamed or its meaning changes (new fields need nothing: reconcile).
local function migrate(data: any): Profile
	TableUtil.reconcile(data, DataTemplate.new() :: any)
	data.version = DataTemplate.version
	return data :: Profile
end

-- Loading ------------------------------------------------------------------------

local function loadProfile(player: Player): Profile?
	local key = STORE.keyPrefix .. player.UserId
	local claimed: Record? = nil

	for attempt = 1, STORE.loadAttempts + 1 do
		local steal = attempt > STORE.loadAttempts
		local lockedByOther = false
		local ok, err = pcall(store.update, key, function(old: Record?): Record?
			local record: Record = old or { data = nil, meta = {} }
			record.meta = record.meta or {}
			local session = record.meta.session
			local alive = session ~= nil and now() - session.time < STORE.lockTimeoutSeconds
			if session and not isMine(session) and alive and not steal then
				lockedByOther = true
				return nil -- cancel the write, try again later
			end
			record.meta.session = mySession()
			claimed = record
			return record
		end)
		if not ok then
			claimed = nil -- the transform ran but the write failed
		end
		if claimed then
			break
		end
		if not ok then
			warn(string.format("[DataService] load %s attempt %d failed: %s", key, attempt, tostring(err)))
		elseif lockedByOther then
			warn(string.format("[DataService] %s is locked by another server, retrying", key))
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(STORE.loadRetryDelay)
	end

	if claimed == nil then
		return nil
	end
	local data = claimed.data
	if type(data) ~= "table" then
		data = DataTemplate.new()
	end
	return migrate(data)
end

-- Saving -------------------------------------------------------------------------

-- Returns false if the session lock was lost.
local function saveEntry(player: Player, entry: Entry, release: boolean): boolean
	if entry.released then
		return true
	end
	if release then
		entry.released = true
	end
	while entry.saving do
		task.wait()
	end
	entry.saving = true
	local lost = false
	local snapshot = sanitize(entry.profile)
	for attempt = 1, STORE.saveAttempts do
		local ok, err = pcall(store.update, entry.key, function(old: Record?): Record?
			local meta = if old and old.meta then old.meta else {}
			if meta.session and not isMine(meta.session) then
				lost = true
				return nil
			end
			return {
				data = snapshot,
				meta = {
					session = if release then nil else mySession(),
					saves = (meta.saves or 0) + 1,
					lastSave = now(),
				},
			}
		end)
		if ok then
			break
		end
		warn(string.format("[DataService] save %s attempt %d failed: %s", entry.key, attempt, tostring(err)))
		task.wait(STORE.saveRetryDelay)
	end
	entry.saving = false

	if lost then
		entry.released = true
		warn("[DataService] session lock for " .. entry.key .. " was taken by another server")
		if player.Parent then
			player:Kick("Your cafe was opened on another server. Please rejoin.")
		end
		return false
	end
	return true
end

-- API ----------------------------------------------------------------------------

function DataService.get(player: Player): Profile?
	local entry = entries[player]
	return if entry and not entry.released then entry.profile else nil
end

-- Yields until the player's profile is loaded (nil if they left first).
function DataService.waitFor(player: Player): Profile?
	while player.Parent and entries[player] == nil do
		task.wait(0.1)
	end
	return DataService.get(player)
end

function DataService.isMock(): boolean
	return usingMock
end

function DataService.save(player: Player)
	local entry = entries[player]
	if entry then
		saveEntry(player, entry, false)
	end
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if profile == nil then
		if player.Parent then
			player:Kick("Could not load your cafe. Please rejoin in a minute.")
		end
		return
	end
	local entry: Entry = {
		profile = profile,
		key = STORE.keyPrefix .. player.UserId,
		saving = false,
		released = false,
	}
	if player.Parent == nil then
		-- left while loading: just give the lock back
		saveEntry(player, entry, true)
		return
	end
	entries[player] = entry
	DataService.loaded:fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	DataService.releasing:fire(player, entry.profile)
	saveEntry(player, entry, true)
	entries[player] = nil
end

function DataService.init()
	store = chooseStore()
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(onPlayerRemoving, player)
	end)

	-- Autosave, spread over the interval so we never burst the DataStore budget.
	task.spawn(function()
		while true do
			task.wait(Economy.autosaveInterval)
			local players = {}
			for player in entries do
				table.insert(players, player)
			end
			local gap = Economy.autosaveInterval / math.max(#players, 1) * 0.5
			for _, player in players do
				local entry = entries[player]
				if entry and not entry.released then
					task.spawn(saveEntry, player, entry, false)
				end
				task.wait(gap)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, entry in entries do
			pending += 1
			task.spawn(function()
				DataService.releasing:fire(player, entry.profile)
				saveEntry(player, entry, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + STORE.shutdownTimeout
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
