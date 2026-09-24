--!nonstrict
-- WorldService: small world rules. Players who fall into the sea are put back on the plaza (or
-- back at their raid's spawn), and characters get the game's base stats on spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)

local RaidService = require(script.Parent.RaidService)

local WorldService = {}

local FALL_Y = -22

local function hubSpawn(): CFrame
	local plaza = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plaza")
	local spawn = plaza and plaza:FindFirstChild("Spawn")
	if spawn then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 10, 26)
end

local function rescueLoop()
	while true do
		task.wait(1.5)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < FALL_Y then
				if RaidService.isRaiding(player) then
					-- Falling off an arena ends that run as a retreat.
					character:PivotTo(hubSpawn())
				else
					character:PivotTo(hubSpawn())
				end
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

function WorldService.init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.MaxHealth = Balance.Player.MaxHealth
				humanoid.Health = Balance.Player.MaxHealth
				humanoid.WalkSpeed = Balance.Player.WalkSpeed
			end
		end)
	end)
	task.spawn(rescueLoop)
end

return WorldService
