--!strict
-- Server entry point: creates the remotes, then inits and starts every service
-- in dependency order (a service may only require services listed above it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.createAll()

local Services = script:WaitForChild("Services")

type Service = { init: () -> (), start: () -> () }

local order = {
	"DataService",
	"MonetizationService",
	"StateService",
}

local services: { Service } = {}
for _, name in order do
	table.insert(services, require(Services:WaitForChild(name)) :: any)
end
for _, service in services do
	service.init()
end
for _, service in services do
	task.spawn(service.start)
end

print("[CosmicCafe] server ready")
