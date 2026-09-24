--!nonstrict
-- Guards: NPC defenders spawned at guard docks inside an arena. They patrol near their dock,
-- chase raiders within their leash, and attack in melee. Dogs also spill coins from the sack.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pieces = require(Shared.Data.Pieces)
local Net = require(Shared.Net.Net)

local Effects = require(script.Parent.Effects)
local Rig = require(script.Parent.Rig)

local Guards = {}

local THINK = 0.35
local REPATH = 0.8

local function spawnPoint(model: Model): Vector3
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "Spawn" then
			return descendant.WorldPosition
		end
	end
	return model:GetPivot().Position + Vector3.new(0, 4, 0)
end

local function nearestRaider(origin: Vector3, range: number, context)
	local best, bestDist = nil, range
	for _, player in Players:GetPlayers() do
		if context.isRaider(player) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local dist = (root.Position - origin).Magnitude
				if dist < bestDist then
					best, bestDist = player, dist
				end
			end
		end
	end
	return best, bestDist
end

function Guards.attach(entry, context)
	local dock, level, id = entry.model, entry.piece.lvl, entry.piece.id
	local speed = Pieces.stat(id, level, "speed")
	local damage = Pieces.stat(id, level, "damage")
	local leash = Pieces.stat(id, level, "leash")
	local attackRange = Pieces.stat(id, level, "attackRange")
	local cooldown = Pieces.stat(id, level, "cooldown")
	local spill = Pieces.stat(id, level, "spill")
	local hp = Pieces.hp(id, level)

	local home = spawnPoint(dock)
	local npc = Rig.build(id, id == "GuardDog" and 0.75 or 1)
	npc:PivotTo(CFrame.new(home))
	npc.Parent = context.container or workspace
	pcall(function()
		npc.PrimaryPart:SetNetworkOwner(nil)
	end)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = hp
	humanoid.Health = hp
	humanoid.WalkSpeed = speed
	npc:SetAttribute("PieceId", id)
	npc:SetAttribute("PieceIndex", dock:GetAttribute("PieceIndex"))
	npc:SetAttribute("Guard", true)
	local stopAnim = Rig.animate(npc)

	local alive = true
	local lastAttack = 0
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	local waypoints = {}
	local waypointIndex = 1
	local lastPath = 0
	local patrolTarget = home
	local rng = Random.new()

	local function moveToward(target: Vector3)
		local clock = os.clock()
		if clock - lastPath > REPATH then
			lastPath = clock
			local ok = pcall(function()
				path:ComputeAsync(npc.PrimaryPart.Position, target)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				waypoints = path:GetWaypoints()
				waypointIndex = 2
			else
				waypoints = {}
			end
		end
		if #waypoints >= waypointIndex then
			local wp = waypoints[waypointIndex]
			if (npc.PrimaryPart.Position - wp.Position).Magnitude < 3 then
				waypointIndex += 1
				wp = waypoints[waypointIndex]
			end
			if wp then
				if wp.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				humanoid:MoveTo(wp.Position)
				return
			end
		end
		humanoid:MoveTo(target)
	end

	task.spawn(function()
		while alive and npc.Parent and humanoid.Health > 0 do
			local origin = npc.PrimaryPart.Position
			local target, dist = nearestRaider(home, leash, context)
			if target then
				local root = target.Character:FindFirstChild("HumanoidRootPart")
				local toTarget = (root.Position - origin).Magnitude
				if toTarget <= attackRange then
					humanoid:MoveTo(origin)
					if os.clock() - lastAttack >= cooldown then
						lastAttack = os.clock()
						Effects.damage(target, damage, id)
						if spill > 0 then
							context.sackSpill(target, spill, origin)
						end
						Net.Server.fireAll("GuardFx", npc, "Attack", { target = target })
						context.onTrigger(id, target)
					end
				else
					moveToward(root.Position)
				end
				local _ = dist
			else
				-- Patrol around the dock.
				if (origin - patrolTarget).Magnitude < 3 or rng:NextNumber() < 0.05 then
					patrolTarget = home + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8))
				end
				humanoid:MoveTo(patrolTarget)
			end
			task.wait(THINK)
		end
		if npc.Parent then
			humanoid:MoveTo(npc.PrimaryPart.Position)
		end
	end)

	humanoid.Died:Connect(function()
		alive = false
		stopAnim()
		Net.Server.fireAll("GuardFx", npc, "Died")
		task.delay(1.5, function()
			npc:Destroy()
		end)
	end)

	return {
		Model = npc,
		Disconnect = function()
			alive = false
			stopAnim()
			if npc.Parent then
				npc:Destroy()
			end
		end,
	}
end

function Guards.isGuard(pieceId: string): boolean
	return pieceId == "GuardBot" or pieceId == "GuardDog"
end

return Guards
