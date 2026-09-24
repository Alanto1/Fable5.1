--!nonstrict
-- EffectsController: juice. Camera shake, hit flashes, bursts, coin fountains and sounds.
-- Everything here is cosmetic and local; nothing affects game state.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.Data.AssetIds)
local Net = require(Shared.Net.Net)

local ClientData = require(script.Parent.ClientData)

local EffectsController = {}

local camera = workspace.CurrentCamera
local shakeAmount = 0
local shakeDecay = 6
local sounds: { [string]: Sound } = {}

local function sfxEnabled(): boolean
	local settings = ClientData.get("Settings")
	return settings == nil or settings.Sfx ~= false
end

local function shakeEnabled(): boolean
	local settings = ClientData.get("Settings")
	return settings == nil or settings.Shake ~= false
end

function EffectsController.sound(name: string, volume: number?, pitch: number?)
	if not sfxEnabled() then
		return
	end
	local id = AssetIds.Sounds[name]
	if not id or id == "" then
		return
	end
	local sound = sounds[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Parent = SoundService
		sounds[name] = sound
	end
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	pcall(function()
		sound:Play()
	end)
end

function EffectsController.soundAt(name: string, position: Vector3, volume: number?)
	if not sfxEnabled() then
		return
	end
	local id = AssetIds.Sounds[name]
	if not id or id == "" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.RollOffMaxDistance = 90
	sound.PlaybackSpeed = 0.95 + math.random() * 0.1
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 3)
end

function EffectsController.shake(amount: number)
	if shakeEnabled() then
		shakeAmount = math.min(2.5, shakeAmount + amount)
	end
end

-- Flash a part white and tween back. Safe on server-owned parts (local only).
function EffectsController.flash(part: BasePart, color: Color3?)
	if not part or not part:IsA("BasePart") then
		return
	end
	local original = part.Color
	part.Color = color or Color3.new(1, 1, 1)
	TweenService:Create(part, TweenInfo.new(0.18), { Color = original }):Play()
end

local function burst(
	position: Vector3,
	color: Color3,
	count: number,
	speed: number,
	size: NumberSequence,
	life: number
)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Position = position
	anchor.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = size
	emitter.Lifetime = NumberRange.new(life * 0.6, life)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Drag = 2
	emitter.LightEmission = 0.4
	emitter.Parent = anchor
	emitter:Emit(count)
	Debris:AddItem(anchor, life + 0.5)
end

function EffectsController.burst(position: Vector3, color: Color3, count: number?)
	burst(
		position,
		color,
		count or 12,
		22,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		0.7
	)
end

function EffectsController.coinFountain(position: Vector3, count: number?)
	burst(
		position,
		Color3.fromRGB(255, 205, 60),
		count or 40,
		34,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0.2) }),
		1.3
	)
end

function EffectsController.sparks(position: Vector3, color: Color3)
	burst(
		position,
		color,
		18,
		28,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		0.5
	)
end

-- Floating text at a world position ("+25", "OUCH").
function EffectsController.popup(position: Vector3, text: string, color: Color3?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 40)
	gui.AlwaysOnTop = true
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 220, 90)
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextSize = 26
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	TweenService:Create(
		gui,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 5, 0) }
	):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()
	Debris:AddItem(anchor, 1)
end

-- A quick beam between two points (zapper).
function EffectsController.beam(from: Vector3, to: Vector3, color: Color3, seconds: number?)
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = from
	holder.Parent = workspace
	a0.Parent = holder
	a1.Parent = holder
	a0.WorldPosition = from
	a1.WorldPosition = to
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = 0.6
	beam.Width1 = 0.3
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = holder
	Debris:AddItem(holder, seconds or 0.2)
end

local function onHitFx(part, fraction, pieceId)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	EffectsController.flash(part)
	EffectsController.sparks(part.Position, part.Color)
	EffectsController.soundAt("Hit", part.Position, 0.5)
	local root = Players.LocalPlayer.Character
		and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - part.Position).Magnitude < 20 then
		EffectsController.shake(0.25)
	end
	local _ = fraction
	local _ = pieceId
end

local function onBreakFx(position, pieceId)
	if typeof(position) ~= "Vector3" then
		return
	end
	if pieceId == "Vault" then
		EffectsController.coinFountain(position, 60)
		EffectsController.soundAt("Win", position, 0.8)
		EffectsController.shake(1.2)
	else
		EffectsController.burst(position, Color3.fromRGB(200, 200, 210), 20)
		EffectsController.soundAt("Break", position, 0.7)
		if pieceId == "Mine" then
			EffectsController.coinFountain(position, 14)
		end
	end
end

local function onTrapFx(model, kind, extra)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local position = model:GetPivot().Position
	local me = Players.LocalPlayer
	local mine = extra and extra.player == me
	if kind == "Spike" then
		EffectsController.sparks(position, Color3.fromRGB(230, 70, 70))
		EffectsController.soundAt("Hit", position, 0.6)
	elseif kind == "Fling" then
		EffectsController.burst(position, Color3.fromRGB(255, 240, 120), 16)
		EffectsController.soundAt("Fling", position, 0.8)
		EffectsController.shake(0.6)
	elseif kind == "Freeze" then
		EffectsController.burst(position, Color3.fromRGB(180, 240, 255), 18)
		if mine then
			EffectsController.popup(position + Vector3.new(0, 3, 0), "FROZEN", Color3.fromRGB(180, 240, 255))
		end
	elseif kind == "Pit" then
		EffectsController.burst(position, Color3.fromRGB(60, 50, 40), 14)
		if mine then
			EffectsController.shake(0.8)
			EffectsController.popup(position + Vector3.new(0, 3, 0), "TRAPPED", Color3.fromRGB(255, 120, 120))
		end
	elseif kind == "Bear" then
		EffectsController.sparks(position, Color3.fromRGB(230, 230, 240))
		EffectsController.soundAt("Hit", position, 0.7)
		if mine then
			EffectsController.popup(position + Vector3.new(0, 3, 0), "SNAP!", Color3.fromRGB(255, 120, 120))
		end
	elseif kind == "FlameOn" then
		EffectsController.soundAt("Fling", position, 0.15)
	end
end

local function onTurretFx(model, kind, extra)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	if kind == "CannonFire" and extra and extra.from then
		EffectsController.burst(extra.from, Color3.fromRGB(255, 200, 120), 10)
		EffectsController.soundAt("Break", extra.from, 0.4)
	elseif kind == "CannonHit" and extra and extra.position then
		EffectsController.burst(extra.position, Color3.fromRGB(255, 140, 60), 18)
		EffectsController.shake(0.4)
	elseif kind == "Zap" and extra and extra.targets then
		local from = model:GetPivot().Position + Vector3.new(0, 5.7, 0)
		for _, target in extra.targets do
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if root then
				EffectsController.beam(from, root.Position, Color3.fromRGB(120, 200, 255), 0.25)
			end
		end
		EffectsController.soundAt("Hit", from, 0.4)
	elseif kind == "GooFire" and extra and extra.to then
		EffectsController.burst(extra.to, Color3.fromRGB(120, 220, 90), 16)
	end
end

local function onGuardFx(npc, kind, extra)
	if typeof(npc) ~= "Instance" or not npc:IsA("Model") then
		return
	end
	local position = npc:GetPivot().Position
	if kind == "Attack" then
		EffectsController.sparks(position, Color3.fromRGB(230, 70, 70))
		if extra and extra.target == Players.LocalPlayer then
			EffectsController.shake(0.5)
		end
	elseif kind == "Died" then
		EffectsController.burst(position, Color3.fromRGB(120, 130, 150), 24)
		EffectsController.soundAt("Break", position, 0.6)
	end
end

function EffectsController.init()
	RunService.RenderStepped:Connect(function(dt)
		if shakeAmount > 0.01 then
			local offset =
				Vector3.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
			camera.CFrame = camera.CFrame * CFrame.new(offset * 0.4)
			shakeAmount = math.max(0, shakeAmount - shakeDecay * dt * shakeAmount)
		end
	end)
	Net.Client.on("HitFx", onHitFx)
	Net.Client.on("BreakFx", onBreakFx)
	Net.Client.on("TrapFx", onTrapFx)
	Net.Client.on("TurretFx", onTurretFx)
	Net.Client.on("GuardFx", onGuardFx)
end

return EffectsController
