--!nonstrict
-- RaidController: the raid offer card, the in-raid HUD (clock, sack, hammer, dash), inputs,
-- and the results screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local ClientData = require(script.Parent.ClientData)
local HudController = require(script.Parent.HudController)
local HubController = require(script.Parent.HubController)
local InputController = require(script.Parent.InputController)
local EffectsController = require(script.Parent.EffectsController)
local HammerController = require(script.Parent.HammerController)

local RaidController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local raidRoot, clockLabel, sackSetter, sackLabel, banner, countdownLabel, targetLabel
local hammerButton, dashButton, sprintButton
local inRaid = false
local endsAt = 0
local lastSwing = 0
local lastDash = 0
local sprinting = false
local connections = {}
local currentOffer = nil
local resultsFrame = nil
local raidsCompleted = 0
local arenaIndex = nil

------------------------------------------------------------------------------------------------
-- Offer card
------------------------------------------------------------------------------------------------

local offerFrame, offerFields

local function buildOffer()
	offerFrame =
		HudController.modal({ Name = "Offer", Size = UDim2.new(0, 520, 0, 360), Title = "TARGET FOUND" })
	local body = offerFrame:FindFirstChild("Body")
	offerFields = {}
	offerFields.name = Components.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = body,
	})
	offerFields.meta = Components.Text({
		Text = "",
		TextSize = 16,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 44),
		Parent = body,
	})
	offerFields.loot = Components.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Color = Theme.Colors.Coin,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 80),
		Parent = body,
	})
	offerFields.detail = Components.Text({
		Text = "",
		TextSize = 15,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 0, 120),
		VAlign = Enum.TextYAlignment.Top,
		Parent = body,
	})

	local _, goApi = Components.Button({
		Name = "Go",
		Text = "RAID!",
		TextSize = 26,
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Size = UDim2.new(0.5, -6, 0, 64),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = body,
		OnClick = function()
			if currentOffer then
				Net.Client.fire("AcceptRaid", currentOffer.id)
				HudController.close()
			end
		end,
	})
	offerFields.go = goApi
	local reroll, rerollApi = Components.Button({
		Name = "ReRoll",
		Text = "RE-ROLL",
		TextSize = 18,
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Size = UDim2.new(0.5, -6, 0, 64),
		Position = UDim2.new(1, 0, 1, 0),
		Anchor = Vector2.new(1, 1),
		Parent = body,
		OnClick = function()
			Net.Client.fire("ReRoll")
		end,
	})
	offerFields.reroll = rerollApi
	offerFields.rerollButton = reroll
	HudController.registerScreen("Offer", function()
		return offerFrame
	end)
end

local function showOffer(offer)
	currentOffer = offer
	local kindText = ({ Live = "ONLINE NOW", Pool = "Player base", Bandit = "Bandit base" })[offer.kind]
		or offer.kind
	offerFields.name.Text = offer.name
	offerFields.meta.Text = ("%s  •  Base Lv %d  •  Defense %d"):format(
		kindText,
		offer.level,
		offer.rating
	)
	offerFields.loot.Text = (offer.lootExact and "Loot: " or "Loot ≈ ")
		.. Format.short(offer.loot)
		.. " coins"
	local detail = ("You have %d seconds. Break in, crack the vault, carry the coins to the EXIT."):format(
		offer.duration
	)
	if offer.revenge then
		detail = "REVENGE RAID. They robbed you. Return the favour."
	elseif offer.tutorial then
		detail = "Your first raid. Follow the prompts and bring the coins home."
	end
	offerFields.detail.Text = detail
	if offer.revenge then
		offerFields.rerollButton.Visible = false
	else
		offerFields.rerollButton.Visible = true
		if offer.freeReRolls > 0 then
			offerFields.reroll.setText(("RE-ROLL (%d free)"):format(offer.freeReRolls))
		else
			offerFields.reroll.setText(("RE-ROLL (%d coins)"):format(offer.reRollCost))
		end
	end
	HudController.open("Offer")
	EffectsController.sound("Tick", 0.4)
end

------------------------------------------------------------------------------------------------
-- Raid HUD
------------------------------------------------------------------------------------------------

local function buildRaidHud()
	raidRoot = Make("Frame", {
		Name = "RaidHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = HudController.hudLayer(),
	})

	-- Clock, top centre
	local clockFrame = Components.Panel({
		Name = "Clock",
		Size = UDim2.new(0, 190, 0, 70),
		Position = UDim2.new(0.5, 0, 0, 12),
		Anchor = Vector2.new(0.5, 0),
		Parent = raidRoot,
	})
	clockLabel = Components.Text({
		Text = "1:30",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = clockFrame,
	})
	targetLabel = Components.Text({
		Text = "",
		TextSize = 14,
		Color = Theme.Colors.TextMuted,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.new(0, 400, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 86),
		Anchor = Vector2.new(0.5, 0),
		Parent = raidRoot,
	})

	-- Sack, top left under currencies
	local sackFrame = Components.Panel({
		Name = "Sack",
		Size = UDim2.new(0, 260, 0, 64),
		Position = UDim2.new(0, 16, 0, 60),
		Parent = raidRoot,
	})
	Components.Text({
		Text = "LOOT SACK",
		Font = Theme.Fonts.Display,
		TextSize = 14,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = sackFrame,
	})
	local _, setter = Components.ProgressBar({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 20),
		Color = Theme.Colors.Coin,
		Value = 0,
		Label = "0 / 0",
		Parent = sackFrame,
	})
	sackSetter = setter
	sackLabel = Components.Text({
		Text = "",
		TextSize = 12,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -2),
		Anchor = Vector2.new(0, 1),
		Parent = sackFrame,
	})

	-- Banner, centre
	banner = Components.Text({
		Name = "Banner",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 44,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 0.28, 0),
		Color = Theme.Colors.Coin,
		Parent = raidRoot,
		[1] = Make("UIStroke", { Color = Theme.Colors.TextDark, Thickness = 3 }),
	})
	banner.Visible = false

	countdownLabel = Components.Text({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 120,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 160),
		Position = UDim2.new(0, 0, 0.35, 0),
		Parent = raidRoot,
		[1] = Make("UIStroke", { Color = Theme.Colors.TextDark, Thickness = 4 }),
	})
	countdownLabel.Visible = false

	-- Touch buttons
	hammerButton = Components.Button({
		Name = "Hammer",
		Text = "SMASH",
		TextSize = 22,
		Color = Theme.Colors.Primary,
		ColorDark = Theme.Colors.PrimaryDark,
		Size = UDim2.new(0, 110, 0, 110),
		Position = UDim2.new(1, -30, 1, -30),
		Anchor = Vector2.new(1, 1),
		Radius = 55,
		Parent = raidRoot,
		OnClick = function()
			RaidController.swing()
		end,
	})
	dashButton = Components.Button({
		Name = "Dash",
		Text = "DASH",
		TextSize = 18,
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Size = UDim2.new(0, 84, 0, 84),
		Position = UDim2.new(1, -160, 1, -40),
		Anchor = Vector2.new(1, 1),
		Radius = 42,
		Parent = raidRoot,
		OnClick = function()
			RaidController.dash()
		end,
	})
	sprintButton = Components.Button({
		Name = "Sprint",
		Text = "RUN",
		TextSize = 16,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0, 70, 0, 70),
		Position = UDim2.new(1, -250, 1, -50),
		Anchor = Vector2.new(1, 1),
		Radius = 35,
		Parent = raidRoot,
		OnClick = function()
			RaidController.setSprint(not sprinting)
		end,
	})

	Components.Button({
		Name = "Leave",
		Text = "GIVE UP",
		TextSize = 14,
		Color = Theme.Colors.Stroke,
		ColorDark = Theme.Colors.Background,
		Size = UDim2.new(0, 100, 0, 34),
		Position = UDim2.new(1, -16, 0, 12),
		Anchor = Vector2.new(1, 0),
		Parent = raidRoot,
		OnClick = function()
			Net.Client.fire("LeaveRaid")
		end,
	})
end

local function showBanner(text: string, color: Color3?, seconds: number?)
	banner.Text = text
	banner.TextColor3 = color or Theme.Colors.Coin
	banner.Visible = true
	local scale = banner:FindFirstChildOfClass("UIScale") or Make("UIScale", { Scale = 1, Parent = banner })
	scale.Scale = 0.6
	TweenService:Create(scale, Theme.Anim.Pop, { Scale = 1 }):Play()
	task.delay(seconds or 2, function()
		if banner.Text == text then
			banner.Visible = false
		end
	end)
end

------------------------------------------------------------------------------------------------
-- Inputs
------------------------------------------------------------------------------------------------

local function findSwingTarget(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- Mouse users aim with the cursor; touch and gamepad aim where the character faces.
	local origin, direction
	if InputController.Device == "Keyboard" then
		local mouse = player:GetMouse()
		local hit = mouse.Target
		if
			hit
			and (hit.Position - root.Position).Magnitude
				<= Balance.Raid.SwingRange + hit.Size.Magnitude / 2
		then
			return hit
		end
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		origin, direction = ray.Origin, ray.Direction * 200
	else
		origin = root.Position + Vector3.new(0, 1, 0)
		direction = root.CFrame.LookVector * Balance.Raid.SwingRange
	end
	local result = workspace:Raycast(origin, direction, params)
	if result and result.Instance then
		local part = result.Instance
		if (part.Position - root.Position).Magnitude <= Balance.Raid.SwingRange + part.Size.Magnitude / 2 then
			return part
		end
	end
	-- Fallback: nearest hittable part in front of the player within range.
	local best, bestDist = nil, Balance.Raid.SwingRange
	local raidFolder = arenaIndex ~= nil and workspace:FindFirstChild("Raid_" .. arenaIndex) or nil
	if raidFolder then
		for _, descendant in raidFolder:GetDescendants() do
			if
				descendant:IsA("BasePart")
				and descendant.Name ~= "Root"
				and descendant.Name ~= "Trigger"
				and descendant.Name ~= "Pile"
			then
				local toPart = descendant.Position - root.Position
				local dist = toPart.Magnitude
				if dist < bestDist and toPart.Unit:Dot(root.CFrame.LookVector) > 0.3 then
					best, bestDist = descendant, dist
				end
			end
		end
	end
	return best
end

function RaidController.swing()
	if not inRaid then
		return
	end
	local clock = os.clock()
	if clock - lastSwing < Balance.Raid.SwingCooldown then
		return
	end
	lastSwing = clock
	local target = findSwingTarget()
	Net.Client.fire("Swing", target)
	if player.Character then
		HammerController.swing(player.Character)
	end
	EffectsController.sound("Hit", target and 0.5 or 0.2, target and 1 or 1.3)
end

function RaidController.dash()
	if not inRaid then
		return
	end
	local clock = os.clock()
	if clock - lastDash < Balance.Player.DashCooldown then
		return
	end
	lastDash = clock
	Net.Client.fire("Dash")
	EffectsController.sound("Fling", 0.3, 1.4)
	EffectsController.shake(0.2)
	local _, api = dashButton, nil
	local _ = api
end

function RaidController.setSprint(state: boolean)
	if sprinting == state then
		return
	end
	sprinting = state
	Net.Client.fire("SetSprint", state)
	sprintButton.BackgroundColor3 = state and Theme.Colors.Coin or Theme.Colors.Success
end

local function bindRaidInput()
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				RaidController.swing()
			elseif
				input.KeyCode == Enum.KeyCode.Q
				or input.KeyCode == Enum.KeyCode.ButtonL1
				or input.KeyCode == Enum.KeyCode.ButtonB
			then
				RaidController.dash()
			elseif
				input.KeyCode == Enum.KeyCode.ButtonX
				or input.KeyCode == Enum.KeyCode.ButtonR2
				or input.KeyCode == Enum.KeyCode.F
			then
				RaidController.swing()
			elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
				RaidController.setSprint(true)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
				RaidController.setSprint(false)
			end
		end)
	)
end

local function unbindRaidInput()
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
end

------------------------------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------------------------------

local resultFields

local function buildResults()
	resultsFrame =
		HudController.modal({ Name = "Results", Size = UDim2.new(0, 560, 0, 420), Title = "RAID OVER" })
	local body = resultsFrame:FindFirstChild("Body")
	resultFields = {}
	resultFields.headline = Components.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = body,
	})
	resultFields.loot = Components.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Colors.Coin,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 56),
		Parent = body,
	})
	resultFields.lines = Components.Text({
		Text = "",
		TextSize = 16,
		Align = Enum.TextXAlignment.Center,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.new(0, 0, 0, 104),
		VAlign = Enum.TextYAlignment.Top,
		Parent = body,
	})
	Components.Button({
		Name = "Again",
		Text = "RAID AGAIN",
		TextSize = 22,
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Size = UDim2.new(0.5, -6, 0, 60),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = body,
		OnClick = function()
			HudController.close()
			Net.Client.fire("RequestRaid", "Any")
		end,
	})
	Components.Button({
		Name = "Home",
		Text = "BACK TO BASE",
		TextSize = 18,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0.5, -6, 0, 60),
		Position = UDim2.new(1, 0, 1, 0),
		Anchor = Vector2.new(1, 1),
		Parent = body,
		OnClick = function()
			HudController.close()
		end,
	})
	HudController.registerScreen("Results", function()
		return resultsFrame
	end)
end

local function maybePromptNotifications()
	local settings = ClientData.get("Settings")
	if settings and settings.NotificationsPrompted then
		return
	end
	if raidsCompleted < 2 then
		return
	end
	local allowed = Net.Client.invoke("CanPromptNotifications")
	if not allowed then
		return
	end
	local canOk, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if not canOk or not can then
		return
	end
	local ok = pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
	if ok then
		Net.Client.fire("NotificationsPrompted")
		if settings then
			settings.NotificationsPrompted = true
		end
	end
end

local function showResults(result)
	raidsCompleted += 1
	local headline, color
	if result.outcome == "Extracted" then
		headline = result.clutch and "CLUTCH EXTRACTION!"
			or (result.success and "EXTRACTED!" or "EMPTY HANDED")
		color = result.success and Theme.Colors.Success or Theme.Colors.TextMuted
	elseif result.outcome == "Died" then
		headline, color = "KNOCKED OUT", Theme.Colors.Danger
	elseif result.outcome == "Left" then
		headline, color = "RETREATED", Theme.Colors.TextMuted
	else
		headline, color = "OUT OF TIME", Theme.Colors.Danger
	end
	resultFields.headline.Text = headline
	resultFields.headline.TextColor3 = color
	local lootText = ("+%s coins"):format(Format.commas(result.banked))
	if result.multiplier > 1 then
		lootText ..= (" (x%d)"):format(result.multiplier)
	end
	resultFields.loot.Text = lootText
	local trophyText = result.trophies >= 0 and ("+%d"):format(result.trophies) or tostring(result.trophies)
	resultFields.lines.Text = table.concat({
		("Target: %s"):format(result.target),
		("Trophies: %s (now %d)"):format(trophyText, result.trophiesTotal),
		("Traps triggered: %d"):format(result.traps),
		result.outcome == "Extracted" and ("Time left: %s"):format(Format.clock(result.timeLeft))
			or ("Kept %d%% of the sack"):format(math.floor(Balance.Raid.KeepOnFail * 100)),
	}, "\n")
	HudController.open("Results")
	EffectsController.sound(result.success and "Win" or "Lose", 0.7)
	if result.success then
		task.delay(1.5, maybePromptNotifications)
	end
end

------------------------------------------------------------------------------------------------
-- Raid flow
------------------------------------------------------------------------------------------------

local function startClock()
	task.spawn(function()
		while inRaid do
			local left = endsAt - os.time()
			if endsAt > 0 then
				clockLabel.Text = Format.clock(math.max(0, left))
				clockLabel.TextColor3 = left <= 10 and Theme.Colors.Danger or Theme.Colors.Text
				if left <= 10 and left > 0 then
					EffectsController.sound("Tick", 0.3, left <= 3 and 1.4 or 1)
				end
			end
			task.wait(1)
		end
	end)
end

local function onRaidStarted(info)
	arenaIndex = info.arenaIndex
	inRaid = true
	endsAt = 0
	HudController.close()
	HubController.setRaiding(true)
	raidRoot.Visible = true
	clockLabel.Text = Format.clock(info.duration)
	clockLabel.TextColor3 = Theme.Colors.Text
	targetLabel.Text = ("Raiding %s (Lv %d)"):format(info.target, info.level)
	sackSetter(0, ("0 / %s"):format(Format.short(info.sackCapacity)))
	sackLabel.Text = "Crack the vault to fill it"
	local touch = InputController.isTouch()
	hammerButton.Visible = touch
	dashButton.Visible = touch
	sprintButton.Visible = touch
	bindRaidInput()
	-- Countdown
	countdownLabel.Visible = true
	task.spawn(function()
		for i = info.countdown, 1, -1 do
			if not inRaid then
				return
			end
			countdownLabel.Text = tostring(i)
			countdownLabel.TextColor3 = Theme.Colors.Text
			EffectsController.sound("Tick", 0.5)
			task.wait(1)
		end
		if inRaid then
			countdownLabel.Text = "GO!"
			countdownLabel.TextColor3 = Theme.Colors.Success
			EffectsController.sound("Win", 0.5, 1.3)
			task.wait(0.8)
			countdownLabel.Visible = false
			if info.tutorial then
				showBanner("Smash the walls to get in!", Theme.Colors.Accent, 4)
			end
		end
	end)
end

local function onRaidGo(serverEndsAt)
	endsAt = serverEndsAt
	startClock()
end

local function onSackUpdated(sack, capacity, delta)
	sackSetter(
		capacity > 0 and sack / capacity or 0,
		("%s / %s"):format(Format.short(sack), Format.short(capacity))
	)
	if delta and delta > 0 then
		EffectsController.sound("Coin", 0.5, 1 + math.random() * 0.2)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			EffectsController.popup(root.Position + Vector3.new(0, 3, 0), "+" .. Format.short(delta))
		end
		if sack >= capacity then
			sackLabel.Text = "SACK FULL. Get to the EXIT!"
			showBanner("SACK FULL! RUN!", Theme.Colors.Success, 2)
		else
			sackLabel.Text = "Grab coins, then reach the EXIT"
		end
	elseif delta and delta < 0 then
		EffectsController.popup(
			(
				player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				or workspace.CurrentCamera
			).Position,
			Format.short(delta),
			Theme.Colors.Danger
		)
		EffectsController.sound("Lose", 0.4, 1.4)
	end
end

local function onVaultCracked(loot)
	showBanner(("VAULT CRACKED! %s coins!"):format(Format.short(loot)), Theme.Colors.Coin, 3)
	EffectsController.shake(1)
	sackLabel.Text = "Grab the coins!"
end

local function onRaidEnded(result)
	inRaid = false
	unbindRaidInput()
	RaidController.setSprint(false)
	raidRoot.Visible = false
	banner.Visible = false
	countdownLabel.Visible = false
	showResults(result)
end

local function onRaidLeft()
	inRaid = false
	raidRoot.Visible = false
	HubController.setRaiding(false)
end

function RaidController.init()
	buildOffer()
	buildRaidHud()
	buildResults()
	Net.Client.on("RaidOffer", showOffer)
	Net.Client.on("RaidStarted", onRaidStarted)
	Net.Client.on("RaidGo", onRaidGo)
	Net.Client.on("SackUpdated", onSackUpdated)
	Net.Client.on("VaultCracked", onVaultCracked)
	Net.Client.on("RaidEnded", onRaidEnded)
	Net.Client.on("RaidLeft", onRaidLeft)
	-- Physics impulses on our own character (the client owns character physics).
	Net.Client.on("ApplyImpulse", function(velocity, ragdoll)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or typeof(velocity) ~= "Vector3" then
			return
		end
		if ragdoll then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			root.AssemblyAngularVelocity =
				Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)
			task.delay(1.4, function()
				if humanoid.Parent and humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
			EffectsController.shake(0.8)
		end
		root.AssemblyLinearVelocity = velocity
	end)
	HudController.ScreenClosed:Connect(function(name)
		if name == "Results" then
			HubController.setRaiding(false)
			if raidsCompleted == 1 then
				task.delay(0.5, function()
					HudController.toast(
						"Nice haul! Now press BUILD and place a trap to protect your vault.",
						"info",
						5
					)
				end)
			end
		end
	end)
	Net.Client.on("DashFx", function(who)
		if typeof(who) == "Instance" and who:IsA("Player") and who.Character then
			local root = who.Character:FindFirstChild("HumanoidRootPart")
			if root then
				EffectsController.burst(root.Position, Theme.Colors.Accent, 10)
			end
		end
	end)
end

return RaidController
