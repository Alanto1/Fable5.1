--!nonstrict
-- Turrets: server behaviours for ranged defenses. Each turret runs its own loop while attached.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pieces = require(Shared.Data.Pieces)
local Net = require(Shared.Net.Net)

local Effects = require(script.Parent.Effects)

local Turrets = {}

local SCAN = 0.25

local function headParts(model: Model)
	local parts = {}
	local pivot = model:FindFirstChild("Pivot")
	local origin = pivot and pivot.Position or model:GetPivot().Position
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Head") then
			table.insert(parts, { part = child, offset = CFrame.new(origin):ToObjectSpace(child.CFrame) })
		end
	end
	return parts, origin
end

local function aim(parts, origin: Vector3, target: Vector3)
	local flat = Vector3.new(target.X, origin.Y, target.Z)
	if (flat - origin).Magnitude < 0.5 then
		return
	end
	local look = CFrame.lookAt(origin, flat)
	for _, entry in parts do
		entry.part.CFrame = look * entry.offset
	end
end

local function nearestRaider(origin: Vector3, range: number, context): (Player?, Vector3?)
	local best, bestDist, bestPos = nil, range, nil
	for _, player in Players:GetPlayers() do
		if context.isRaider(player) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local dist = (root.Position - origin).Magnitude
				if dist < bestDist then
					best, bestDist, bestPos = player, dist, root.Position
				end
			end
		end
	end
	return best, bestPos
end

local function muzzleOf(model: Model): Vector3
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "Muzzle" then
			return descendant.WorldPosition
		end
	end
	return model:GetPivot().Position + Vector3.new(0, 4, 0)
end

local function fx(model: Model, kind: string, extra)
	Net.Server.fireAll("TurretFx", model, kind, extra)
end

local behaviours = {}

function behaviours.Cannon(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local range = Pieces.stat("Cannon", level, "range")
	local damage = Pieces.stat("Cannon", level, "damage")
	local cooldown = Pieces.stat("Cannon", level, "cooldown")
	local speed = Pieces.stat("Cannon", level, "projectileSpeed")
	local knockback = Pieces.stat("Cannon", level, "knockback")
	local parts, origin = headParts(model)
	local alive = true
	task.spawn(function()
		while alive and model.Parent do
			local target, pos = nearestRaider(origin, range, context)
			if target and pos then
				aim(parts, origin, pos)
				local muzzle = muzzleOf(model)
				local shell = Instance.new("Part")
				shell.Name = "Shell"
				shell.Shape = Enum.PartType.Ball
				shell.Size = Vector3.new(1.4, 1.4, 1.4)
				shell.Color = Color3.fromRGB(40, 40, 50)
				shell.Material = Enum.Material.Metal
				shell.CanCollide = false
				shell.CFrame = CFrame.new(muzzle)
				local toTarget = (pos + Vector3.new(0, 1, 0) - muzzle)
				-- Lead the shot a little toward where the target is heading.
				local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
				if root then
					toTarget += root.AssemblyLinearVelocity * (toTarget.Magnitude / speed) * 0.6
				end
				shell.AssemblyLinearVelocity = toTarget.Unit * speed
					+ Vector3.new(0, toTarget.Magnitude * 0.35, 0)
				shell.Parent = workspace
				Debris:AddItem(shell, 4)
				local hitOnce = false
				shell.Touched:Connect(function(hit)
					if hitOnce then
						return
					end
					local character = hit.Parent
					local player = character and Players:GetPlayerFromCharacter(character)
					if player and context.isRaider(player) then
						hitOnce = true
						Effects.damage(player, damage, "Cannon")
						local hrp = character:FindFirstChild("HumanoidRootPart")
						if hrp then
							local dir = (hrp.Position - shell.Position)
							dir = Vector3.new(dir.X, 0.4, dir.Z)
							if dir.Magnitude > 0 then
								hrp.AssemblyLinearVelocity = dir.Unit * knockback
							end
						end
						fx(model, "CannonHit", { position = shell.Position })
						context.onTrigger("Cannon", player)
						shell:Destroy()
					elseif
						hit.Anchored
						and hit:IsDescendantOf(workspace)
						and not hit:IsDescendantOf(model)
					then
						hitOnce = true
						fx(model, "CannonHit", { position = shell.Position })
						shell:Destroy()
					end
				end)
				fx(model, "CannonFire", { from = muzzle })
				task.wait(cooldown)
			else
				task.wait(SCAN)
			end
		end
	end)
	return {
		Disconnect = function()
			alive = false
		end,
	}
end

function behaviours.Zapper(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local range = Pieces.stat("Zapper", level, "range")
	local slow = Pieces.stat("Zapper", level, "slow")
	local duration = Pieces.stat("Zapper", level, "duration")
	local cooldown = Pieces.stat("Zapper", level, "cooldown")
	local damage = Pieces.stat("Zapper", level, "damage")
	local origin = muzzleOf(model)
	local alive = true
	task.spawn(function()
		while alive and model.Parent do
			local hit = {}
			for _, player in Players:GetPlayers() do
				if context.isRaider(player) then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and (root.Position - origin).Magnitude <= range then
						table.insert(hit, player)
					end
				end
			end
			if #hit > 0 then
				for _, player in hit do
					Effects.slow(player, slow, duration)
					Effects.damage(player, damage, "Zapper")
					context.onTrigger("Zapper", player)
				end
				fx(model, "Zap", { targets = hit })
				task.wait(cooldown)
			else
				task.wait(SCAN)
			end
		end
	end)
	return {
		Disconnect = function()
			alive = false
		end,
	}
end

function behaviours.GooGun(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local range = Pieces.stat("GooGun", level, "range")
	local cooldown = Pieces.stat("GooGun", level, "cooldown")
	local puddleSlow = Pieces.stat("GooGun", level, "puddleSlow")
	local puddleLife = Pieces.stat("GooGun", level, "puddleLife")
	local parts, origin = headParts(model)
	local alive = true
	task.spawn(function()
		while alive and model.Parent do
			local target, pos = nearestRaider(origin, range, context)
			if target and pos then
				aim(parts, origin, pos)
				local puddle = Instance.new("Part")
				puddle.Name = "Goo"
				puddle.Shape = Enum.PartType.Cylinder
				puddle.Size = Vector3.new(0.3, 6, 6)
				puddle.CFrame = CFrame.new(pos.X, origin.Y - 3.4, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
				puddle.Color = Color3.fromRGB(120, 220, 90)
				puddle.Material = Enum.Material.Neon
				puddle.Transparency = 0.3
				puddle.Anchored = true
				puddle.CanCollide = false
				puddle.Parent = workspace
				Debris:AddItem(puddle, puddleLife)
				puddle.Touched:Connect(function(hit)
					local player = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
					if player and context.isRaider(player) then
						Effects.slow(player, puddleSlow, 0.5)
						context.onTrigger("GooGun", player)
					end
				end)
				fx(model, "GooFire", { from = muzzleOf(model), to = puddle.Position })
				task.wait(cooldown)
			else
				task.wait(SCAN)
			end
		end
	end)
	return {
		Disconnect = function()
			alive = false
		end,
	}
end

function Turrets.attach(entry, context)
	local behaviour = behaviours[entry.piece.id]
	if not behaviour then
		return nil
	end
	return behaviour(entry, context)
end

function Turrets.isTurret(pieceId: string): boolean
	return behaviours[pieceId] ~= nil
end

return Turrets
