--!nonstrict
-- Traps: server behaviours for trap pieces inside a raid arena.
-- Traps.attach(entry, context) wires a piece; the returned cleanup stops it.
-- context: { isRaider = fn(player) -> boolean, onTrigger = fn(pieceId, player), sackSpill = fn(player, fraction) }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pieces = require(Shared.Data.Pieces)
local Net = require(Shared.Net.Net)

local Effects = require(script.Parent.Effects)

local Traps = {}

local DEBOUNCE = 0.3

local function raiderFromHit(hit: BasePart, context): Player?
	local character = hit.Parent
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player and context.isRaider(player) then
		return player
	end
	return nil
end

local function fx(model: Model, kind: string, extra)
	Net.Server.fireAll("TrapFx", model, kind, extra)
end

-- Generic "touch once, rearm after N seconds" wrapper.
local function onTouch(trigger: BasePart, context, rearm: number, handler)
	local armed = true
	local lastByPlayer: { [Player]: number } = {}
	return trigger.Touched:Connect(function(hit)
		if not armed then
			return
		end
		local player = raiderFromHit(hit, context)
		if not player then
			return
		end
		local clock = os.clock()
		if lastByPlayer[player] and clock - lastByPlayer[player] < DEBOUNCE then
			return
		end
		lastByPlayer[player] = clock
		armed = false
		handler(player)
		task.delay(rearm, function()
			armed = true
		end)
	end)
end

local behaviours = {}

function behaviours.SpikeTrap(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local damage = Pieces.stat("SpikeTrap", level, "damage")
	local stun = Pieces.stat("SpikeTrap", level, "stun")
	local rearm = Pieces.stat("SpikeTrap", level, "rearm")
	local spikes = {}
	for _, child in model:GetChildren() do
		if child:GetAttribute("Spike") then
			table.insert(
				spikes,
				{ part = child, down = child.CFrame, up = child.CFrame * CFrame.new(0, 1.6, 0) }
			)
		end
	end
	local function pop()
		for _, spike in spikes do
			TweenService:Create(spike.part, TweenInfo.new(0.08), { CFrame = spike.up }):Play()
		end
		task.delay(0.6, function()
			for _, spike in spikes do
				TweenService:Create(spike.part, TweenInfo.new(0.3), { CFrame = spike.down }):Play()
			end
		end)
	end
	return onTouch(trigger, context, rearm, function(player)
		pop()
		Effects.damage(player, damage, "SpikeTrap")
		Effects.stun(player, stun)
		fx(model, "Spike")
		context.onTrigger("SpikeTrap", player)
	end)
end

function behaviours.Flinger(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local force = Pieces.stat("Flinger", level, "force")
	local rearm = Pieces.stat("Flinger", level, "rearm")
	local paddle = nil
	for _, child in model:GetChildren() do
		if child:GetAttribute("Paddle") then
			paddle = child
		end
	end
	return onTouch(trigger, context, rearm, function(player)
		if paddle then
			local rest = paddle.CFrame
			TweenService:Create(paddle, TweenInfo.new(0.08), { CFrame = rest * CFrame.Angles(-0.9, 0, 0) })
				:Play()
			task.delay(0.4, function()
				TweenService:Create(paddle, TweenInfo.new(0.4), { CFrame = rest }):Play()
			end)
		end
		Effects.fling(player, model:GetPivot().Position, force)
		fx(model, "Fling")
		context.onTrigger("Flinger", player)
	end)
end

function behaviours.FlameJet(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local flame = nil
	for _, child in model:GetChildren() do
		if child:GetAttribute("Flame") then
			flame = child
		end
	end
	local light = model:FindFirstChildOfClass("PointLight")
	local onTime = Pieces.stat("FlameJet", level, "onTime")
	local offTime = Pieces.stat("FlameJet", level, "offTime")
	local tickDamage = Pieces.stat("FlameJet", level, "tickDamage")
	local tickRate = Pieces.stat("FlameJet", level, "tickRate")
	local inside: { [Player]: number } = {}
	local alive = true

	local touched = trigger.Touched:Connect(function(hit)
		local player = raiderFromHit(hit, context)
		if player then
			inside[player] = os.clock()
		end
	end)
	local ended = trigger.TouchEnded:Connect(function(hit)
		local player = raiderFromHit(hit, context)
		if player then
			inside[player] = nil
		end
	end)

	task.spawn(function()
		-- Random phase so a row of jets is not synchronised.
		task.wait(math.random() * (onTime + offTime))
		while alive do
			if flame then
				flame.Transparency = 0.25
			end
			if light then
				light.Brightness = 2
			end
			fx(model, "FlameOn")
			local endAt = os.clock() + onTime
			while alive and os.clock() < endAt do
				for player, since in inside do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					-- TouchEnded can be missed; drop players who are clearly out of the column.
					if not root or (root.Position - trigger.Position).Magnitude > 5 then
						inside[player] = nil
					else
						Effects.damage(player, tickDamage, "FlameJet")
						context.onTrigger("FlameJet", player)
					end
					local _ = since
				end
				task.wait(tickRate)
			end
			if flame then
				flame.Transparency = 1
			end
			if light then
				light.Brightness = 0
			end
			fx(model, "FlameOff")
			task.wait(offTime)
		end
	end)

	return {
		Disconnect = function()
			alive = false
			touched:Disconnect()
			ended:Disconnect()
		end,
	}
end

function behaviours.FreezePad(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local slow = Pieces.stat("FreezePad", level, "slow")
	local duration = Pieces.stat("FreezePad", level, "duration")
	local rearm = Pieces.stat("FreezePad", level, "rearm")
	return onTouch(trigger, context, rearm, function(player)
		Effects.slow(player, slow, duration)
		fx(model, "Freeze", { player = player })
		context.onTrigger("FreezePad", player)
	end)
end

function behaviours.Pit(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local climb = Pieces.stat("Pit", level, "climb")
	local spill = Pieces.stat("Pit", level, "spill")
	local door = nil
	for _, child in model:GetChildren() do
		if child:GetAttribute("Door") then
			door = child
		end
	end
	return onTouch(trigger, context, climb + 1, function(player)
		if door then
			local rest = door.CFrame
			TweenService:Create(
				door,
				TweenInfo.new(0.15),
				{ CFrame = rest * CFrame.new(0, -0.3, 0) * CFrame.Angles(0.5, 0, 0) }
			):Play()
			task.delay(climb, function()
				TweenService:Create(door, TweenInfo.new(0.3), { CFrame = rest }):Play()
			end)
		end
		Effects.root(player, climb)
		context.sackSpill(player, spill, model:GetPivot().Position)
		fx(model, "Pit", { player = player, seconds = climb })
		context.onTrigger("Pit", player)
	end)
end

function behaviours.BearTrap(entry, context)
	local model, level = entry.model, entry.piece.lvl
	local trigger = model:FindFirstChild("Trigger")
	local root = Pieces.stat("BearTrap", level, "root")
	local damage = Pieces.stat("BearTrap", level, "damage")
	local rearm = Pieces.stat("BearTrap", level, "rearm")
	local jaws = {}
	for _, child in model:GetChildren() do
		if child:GetAttribute("Jaw") then
			table.insert(jaws, { part = child, rest = child.CFrame })
		end
	end
	return onTouch(trigger, context, rearm, function(player)
		for _, jaw in jaws do
			local closed = jaw.rest * CFrame.Angles(jaw.part:GetAttribute("Jaw") == "L" and 1.2 or -1.2, 0, 0)
			TweenService:Create(jaw.part, TweenInfo.new(0.07), { CFrame = closed }):Play()
			task.delay(root, function()
				TweenService:Create(jaw.part, TweenInfo.new(0.4), { CFrame = jaw.rest }):Play()
			end)
		end
		Effects.root(player, root)
		Effects.damage(player, damage, "BearTrap")
		fx(model, "Bear", { player = player, seconds = root })
		context.onTrigger("BearTrap", player)
	end)
end

function Traps.attach(entry, context)
	local behaviour = behaviours[entry.piece.id]
	if not behaviour or not entry.model:FindFirstChild("Trigger") then
		return nil
	end
	return behaviour(entry, context)
end

function Traps.isTrap(pieceId: string): boolean
	return behaviours[pieceId] ~= nil
end

return Traps
