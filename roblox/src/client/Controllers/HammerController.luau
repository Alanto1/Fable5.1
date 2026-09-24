--!nonstrict
-- HammerController: the hammer and loot sack every raiding character wears, plus the swing
-- animation. Driven by character attributes the server sets (Raiding, HammerSkin, SackSkin,
-- SackFill) so every client shows the same thing without extra remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Data.Cosmetics)
local Net = require(Shared.Net.Net)

local HammerController = {}

local SLASH_R15 = "rbxassetid://522635514"
local SLASH_R6 = "rbxassetid://129967390"

local gear: { [Model]: { hammer: Model?, sack: BasePart?, track: AnimationTrack? } } = {}

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
	return w
end

local function buildHammer(skinKey: string): Model
	local skin = Cosmetics.get("Hammers", skinKey) or Cosmetics.Hammers.Classic
	local model = Instance.new("Model")
	model.Name = "Hammer"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 2.6, 0.35)
	handle.Color = rgb(skin.handle)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.6, 0.9, 0.9)
	head.Color = rgb(skin.head)
	head.Material = skin.glow and Enum.Material.Neon or Enum.Material.Metal
	head.CanCollide = false
	head.CanQuery = false
	head.Massless = true
	head.Parent = model
	weld(handle, head, CFrame.new(0, 1.35, 0))
	model.PrimaryPart = handle
	return model
end

local function buildSack(skinKey: string): BasePart
	local skin = Cosmetics.get("Sacks", skinKey) or Cosmetics.Sacks.Classic
	local sack = Instance.new("Part")
	sack.Name = "Sack"
	sack.Shape = Enum.PartType.Ball
	sack.Size = Vector3.new(1.2, 1.2, 1.2)
	sack.Color = rgb(skin.color)
	sack.Material = skin.glow and Enum.Material.Neon or Enum.Material.Fabric
	sack.CanCollide = false
	sack.CanQuery = false
	sack.Massless = true
	return sack
end

local function handOf(character: Model): BasePart?
	local part = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if part and part:IsA("BasePart") then part else nil
end

local function torsoOf(character: Model): BasePart?
	local part = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if part and part:IsA("BasePart") then part else nil
end

local function attach(character: Model)
	if gear[character] then
		return
	end
	local hand = handOf(character)
	local torso = torsoOf(character)
	if not hand or not torso then
		return
	end
	local entry = {}
	local hammerSkin = character:GetAttribute("HammerSkin")
	local hammer = buildHammer(if type(hammerSkin) == "string" then hammerSkin else "Classic")
	hammer.Parent = character
	weld(hand, hammer.PrimaryPart, CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	entry.hammer = hammer
	local sackSkin = character:GetAttribute("SackSkin")
	local sack = buildSack(if type(sackSkin) == "string" then sackSkin else "Classic")
	sack.Parent = character
	weld(torso, sack, CFrame.new(0, 0.2, 0.9))
	entry.sack = sack
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = humanoid.RigType == Enum.HumanoidRigType.R6 and SLASH_R6 or SLASH_R15
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok then
			track.Priority = Enum.AnimationPriority.Action
			entry.track = track
		end
	end
	gear[character] = entry
end

local function detach(character: Model)
	local entry = gear[character]
	if not entry then
		return
	end
	gear[character] = nil
	if entry.hammer then
		entry.hammer:Destroy()
	end
	if entry.sack then
		entry.sack:Destroy()
	end
	if entry.track then
		pcall(function()
			entry.track:Stop()
		end)
	end
end

local function updateSack(character: Model)
	local entry = gear[character]
	if not entry or not entry.sack then
		return
	end
	local fill = character:GetAttribute("SackFill") or 0
	local size = 1.2 + fill * 1.6
	TweenService:Create(entry.sack, TweenInfo.new(0.2), { Size = Vector3.new(size, size, size) }):Play()
end

function HammerController.swing(character: Model)
	local entry = gear[character]
	if entry and entry.track then
		entry.track:Play(0.05, 1, 1.6)
	end
end

local function watch(character: Model)
	local function refresh()
		if character:GetAttribute("Raiding") then
			attach(character)
		else
			detach(character)
		end
	end
	character:GetAttributeChangedSignal("Raiding"):Connect(refresh)
	character:GetAttributeChangedSignal("SackFill"):Connect(function()
		updateSack(character)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			detach(character)
		end
	end)
	task.defer(refresh)
end

local function watchPlayer(player: Player)
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

function HammerController.init()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Net.Client.on("SwingFx", function(player)
		if typeof(player) == "Instance" and player:IsA("Player") and player.Character then
			HammerController.swing(player.Character)
		end
	end)
end

return HammerController
