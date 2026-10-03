--!strict
-- Client entry point. Controllers are added step by step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

Net.event("State").OnClientEvent:Connect(function(snapshot)
	print("[CosmicCafe] state received, money =", snapshot.profile.money)
end)
Net.event("Ready"):FireServer()
