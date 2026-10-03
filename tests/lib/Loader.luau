--!strict
-- Lets Lune run the Roblox-style shared modules unchanged.
--
-- Shared modules use instance requires (`require(script.Parent.Formula)`).
-- This loader builds a fake `script` object over the filesystem: indexing a
-- node by name finds `<name>.luau`, `<name>/init.luau` or the folder `<name>`,
-- `.Parent` walks up, and `require(node)` loads that file with the same
-- fake `script`/`require` injected. Roblox datatypes (Color3, Vector3...)
-- come from @lune/roblox.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

type Node = { __path: string }

local nodeMeta = {}
local nodes: { [string]: Node } = {}
local cache: { [string]: any } = {}

local function nodeAt(path: string): Node
	local existing = nodes[path]
	if existing then
		return existing
	end
	local node = setmetatable({ __path = path }, nodeMeta) :: any
	nodes[path] = node
	return node
end

-- fs calls yield, which is not allowed inside metamethods, so the tree is
-- indexed up front.
local files: { [string]: boolean } = {}
local dirs: { [string]: boolean } = {}
local sources: { [string]: string } = {}

local function scan(dir: string)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		elseif string.sub(name, -5) == ".luau" then
			files[path] = true
			sources[path] = fs.readFile(path)
		end
	end
end
scan("src")

local function parentPath(path: string): string?
	return string.match(path, "^(.*)/[^/]+$")
end

local function childPath(path: string, name: string): string?
	local base = path .. "/" .. name
	if files[base .. ".luau"] or dirs[base] then
		return base
	end
	return nil
end

nodeMeta.__index = function(self: Node, key: string): any
	if key == "Parent" then
		local parent = parentPath(self.__path)
		return if parent then nodeAt(parent) else nil
	elseif key == "Name" then
		return string.match(self.__path, "([^/]+)$")
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(node: Node, name: string)
			local path = childPath(node.__path, name)
			if path == nil then
				if key == "WaitForChild" then
					error("Loader: no child '" .. name .. "' in " .. node.__path)
				end
				return nil
			end
			return nodeAt(path)
		end
	end
	local path = childPath(self.__path, key)
	if path == nil then
		error("Loader: '" .. key .. "' is not a valid member of " .. self.__path)
	end
	return nodeAt(path)
end
nodeMeta.__tostring = function(self: Node)
	return self.__path
end

local function sourceFile(path: string): string
	if files[path .. ".luau"] then
		return path .. ".luau"
	elseif files[path .. "/init.luau"] then
		return path .. "/init.luau"
	end
	error("Loader: no module at " .. path)
end

local requireNode: (node: Node) -> any

requireNode = function(node: Node): any
	local file = sourceFile(node.__path)
	if cache[file] ~= nil then
		return cache[file]
	end
	local chunk = luau.load(sources[file], {
		debugName = file,
		environment = {
			script = node,
			require = requireNode,
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
		},
	})
	local result = chunk()
	cache[file] = if result == nil then false else result
	return result
end

-- Loader.shared("Util/Formula") -> module at src/shared/Util/Formula.luau
function Loader.shared(path: string): any
	return requireNode(nodeAt("src/shared/" .. path))
end

-- Fresh copies of every module (for tests that mutate config).
function Loader.reset()
	table.clear(cache)
end

return Loader
