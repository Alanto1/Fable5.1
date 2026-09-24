--!nonstrict
-- Rig: builds a blocky R6-compatible NPC (guard bot / guard dog) from parts so no uploaded
-- assets are needed. Animations use Roblox-owned default R6 animation ids.

local Rig = {}

local WALK_ANIM = "rbxassetid://180426354"
local IDLE_ANIM = "rbxassetid://180435571"

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

-- kind: "GuardBot" | "GuardDog". Returns the character Model (unparented).
function Rig.build(kind: string, scaleOpt: number?)
	local scale: number = scaleOpt or 1
	local body = kind == "GuardDog" and Color3.fromRGB(120, 90, 60) or Color3.fromRGB(90, 100, 120)
	local accent = kind == "GuardDog" and Color3.fromRGB(255, 160, 60) or Color3.fromRGB(230, 70, 70)

	local model = Instance.new("Model")
	model.Name = kind

	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1) * scale, body)
	hrp.Transparency = 1
	local torso = part("Torso", Vector3.new(2, 2, 1) * scale, body, Enum.Material.Metal)
	local head = part("Head", Vector3.new(2, 1, 1) * scale, body, Enum.Material.Metal)
	local la = part("Left Arm", Vector3.new(1, 2, 1) * scale, body)
	local ra = part("Right Arm", Vector3.new(1, 2, 1) * scale, body)
	local ll = part("Left Leg", Vector3.new(1, 2, 1) * scale, body)
	local rl = part("Right Leg", Vector3.new(1, 2, 1) * scale, body)

	torso.CanCollide = true

	local visor = part("Visor", Vector3.new(1.6, 0.4, 0.2) * scale, accent, Enum.Material.Neon)
	visor.CFrame = head.CFrame * CFrame.new(0, 0.1 * scale, -0.5 * scale)
	local visorWeld = Instance.new("Weld")
	visorWeld.Part0 = head
	visorWeld.Part1 = visor
	visorWeld.C0 = CFrame.new(0, 0.1 * scale, -0.5 * scale)
	visorWeld.Parent = visor

	local chest = part("Chest", Vector3.new(1.2, 0.8, 0.2) * scale, accent, Enum.Material.Neon)
	local chestWeld = Instance.new("Weld")
	chestWeld.Part0 = torso
	chestWeld.Part1 = chest
	chestWeld.C0 = CFrame.new(0, 0.3 * scale, -0.55 * scale)
	chestWeld.Parent = chest

	if kind == "GuardDog" then
		local snout = part("Snout", Vector3.new(1, 0.6, 0.8) * scale, body, Enum.Material.Metal)
		local snoutWeld = Instance.new("Weld")
		snoutWeld.Part0 = head
		snoutWeld.Part1 = snout
		snoutWeld.C0 = CFrame.new(0, -0.2 * scale, -0.8 * scale)
		snoutWeld.Parent = snout
		snout.Parent = model
		local earL = part("EarL", Vector3.new(0.4, 0.8, 0.3) * scale, accent)
		local earWeld = Instance.new("Weld")
		earWeld.Part0 = head
		earWeld.Part1 = earL
		earWeld.C0 = CFrame.new(-0.7 * scale, 0.8 * scale, 0)
		earWeld.Parent = earL
		earL.Parent = model
	end

	-- Standard R6 joint offsets
	local s = scale
	motor(
		"RootJoint",
		hrp,
		torso,
		CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
		CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi)
	)
	motor(
		"Neck",
		torso,
		head,
		CFrame.new(0, 1 * s, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi),
		CFrame.new(0, -0.5 * s, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi)
	)
	motor(
		"Left Shoulder",
		torso,
		la,
		CFrame.new(-1 * s, 0.5 * s, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		CFrame.new(0.5 * s, 0.5 * s, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	)
	motor(
		"Right Shoulder",
		torso,
		ra,
		CFrame.new(1 * s, 0.5 * s, 0) * CFrame.Angles(0, math.pi / 2, 0),
		CFrame.new(-0.5 * s, 0.5 * s, 0) * CFrame.Angles(0, math.pi / 2, 0)
	)
	motor(
		"Left Hip",
		torso,
		ll,
		CFrame.new(-1 * s, -1 * s, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		CFrame.new(-0.5 * s, 1 * s, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	)
	motor(
		"Right Hip",
		torso,
		rl,
		CFrame.new(1 * s, -1 * s, 0) * CFrame.Angles(0, math.pi / 2, 0),
		CFrame.new(0.5 * s, 1 * s, 0) * CFrame.Angles(0, math.pi / 2, 0)
	)

	for _, p in { hrp, torso, head, la, ra, ll, rl, visor, chest } do
		p.Parent = model
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.AutoRotate = true
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	local walk = Instance.new("Animation")
	walk.Name = "Walk"
	walk.AnimationId = WALK_ANIM
	walk.Parent = model
	local idle = Instance.new("Animation")
	idle.Name = "Idle"
	idle.AnimationId = IDLE_ANIM
	idle.Parent = model

	model.PrimaryPart = hrp
	return model
end

-- Starts walk/idle animation switching based on MoveDirection. Returns a cleanup function.
function Rig.animate(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return function() end
	end
	local walkTrack, idleTrack
	local ok = pcall(function()
		walkTrack = animator:LoadAnimation(model:FindFirstChild("Walk") :: Animation)
		idleTrack = animator:LoadAnimation(model:FindFirstChild("Idle") :: Animation)
	end)
	if not ok then
		return function() end
	end
	idleTrack:Play()
	local moving = false
	local connection = humanoid.Running:Connect(function(speed)
		local nowMoving = speed > 0.5
		if nowMoving ~= moving then
			moving = nowMoving
			if moving then
				idleTrack:Stop()
				walkTrack:Play()
			else
				walkTrack:Stop()
				idleTrack:Play()
			end
		end
	end)
	return function()
		connection:Disconnect()
		pcall(function()
			walkTrack:Stop()
			idleTrack:Stop()
		end)
	end
end

return Rig
