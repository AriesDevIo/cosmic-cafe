--!strict
-- Every remote in the game, defined in one place.
--
-- The server creates the RemoteEvents under ReplicatedStorage.Remotes; the
-- client waits for them. Client -> server remotes go through Net.onServerEvent,
-- which rate-limits per player and isolates handler errors. Handlers must still
-- validate every argument (see Util/Validate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require(script.Parent.Util.RateLimiter)

export type RemoteDef = {
	-- sustained calls per second and burst size (client -> server only)
	rate: number?,
	burst: number?,
}

local Net = {}

Net.FOLDER_NAME = "Remotes"

-- Client -> server
Net.clientToServer = {
	Ready = { rate = 0.2, burst = 2 }, -- client finished loading, send it everything
	BuyDish = { rate = 15, burst = 30 }, -- (dishId, amount: 0 = max)
	UnlockWorld = { rate = 2, burst = 4 }, -- (worldId)
	Travel = { rate = 1, burst = 3 }, -- (worldId)
	Hire = { rate = 2, burst = 4 }, -- (worldId, roleId)
	OpenCrate = { rate = 3, burst = 5 }, -- (crateId)
	Fuse = { rate = 2, burst = 4 }, -- ({ staffId x3 })
	Assign = { rate = 4, burst = 8 }, -- (staffId, worldId?)
	Combine = { rate = 2, burst = 4 }, -- ({ ingredientId x2-3 })
	ClaimDaily = { rate = 0.5, burst = 2 },
	Franchise = { rate = 0.2, burst = 1 },
	BuyNode = { rate = 2, burst = 4 }, -- (nodeId)
	SetAutoBuy = { rate = 1, burst = 3 }, -- (enabled)
	PromptPass = { rate = 1, burst = 2 }, -- (passId)
} :: { [string]: RemoteDef }

-- Server -> client
Net.serverToClient = {
	State = {}, -- (snapshot) full save + context, see StateService
	Money = {}, -- (money, runEarnings, lifetimeEarnings) cheap frequent update
	Runtime = {}, -- (runtime) streak / weather / etc.
	Notify = {}, -- (text, style)
	Announce = {}, -- (text, colorHex) server-wide message
	Effect = {}, -- (kind, data) coin pops, sounds
	WelcomeBack = {}, -- (earned, secondsAway, secondsCounted)
	Discovery = {}, -- (kind, id, firstOnServer)
} :: { [string]: RemoteDef }

local function folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Net.FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local created = Instance.new("Folder")
		created.Name = Net.FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(Net.FOLDER_NAME) :: Folder
end

local cache: { [string]: RemoteEvent } = {}

function Net.event(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	assert(Net.clientToServer[name] or Net.serverToClient[name], "Unknown remote " .. name)
	local parent = folder()
	local remote: RemoteEvent
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing then
			remote = existing :: RemoteEvent
		else
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end
	else
		remote = parent:WaitForChild(name) :: RemoteEvent
	end
	cache[name] = remote
	return remote
end

-- Server: create every remote up front so clients never wait forever.
function Net.createAll()
	assert(RunService:IsServer(), "Net.createAll is server only")
	for name in Net.clientToServer do
		Net.event(name)
	end
	for name in Net.serverToClient do
		Net.event(name)
	end
end

local limiters: { [string]: RateLimiter.RateLimiter } = {}

-- Server: rate-limited, error-isolated handler for a client -> server remote.
function Net.onServerEvent(name: string, handler: (player: Player, ...unknown) -> ())
	local def = Net.clientToServer[name]
	assert(def, "Not a client -> server remote: " .. name)
	local limiter = RateLimiter.new(def.rate or 5, def.burst or 10)
	limiters[name] = limiter
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...: unknown)
		if not limiter:check(player, os.clock()) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s from %s failed: %s", name, player.Name, tostring(err)))
		end
	end)
end

-- Server helpers
function Net.fire(player: Player, name: string, ...: any)
	Net.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Net.event(name):FireAllClients(...)
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:forget(player)
		end
	end)
end

return Net
