--!nonstrict
-- HubController: everything on screen while the player is on the island.
-- RAID and BUILD buttons, vault card with COLLECT, level bar, shield timer, raid alerts,
-- the raid-portal and shop prompts, and the side menu entries.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net.Net)
local Signal = require(Shared.Util.Signal)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local ClientData = require(script.Parent.ClientData)
local HudController = require(script.Parent.HudController)
local EffectsController = require(script.Parent.EffectsController)

local HubController = {
	BaseChanged = Signal.new(), -- (state)
	RaidingChanged = Signal.new(), -- (bool)
}

local hubRoot = nil
local raidButton
local setVault, setShield, setLevel, setLevelText
local vaultCollect
local raidLogBadge
local raiding = false
local buildMode = false
local baseState = nil
local pulseTween = nil

local function serverNow(): number
	local state = ClientData.get("Base")
	if state and state.ServerTime and state.ReceivedAt then
		return state.ServerTime + (os.clock() - state.ReceivedAt)
	end
	return os.time()
end

local function refreshVault()
	if not baseState then
		return
	end
	local stored, capacity = baseState.Stored, baseState.Capacity
	local fraction = capacity > 0 and stored / capacity or 0
	setVault(fraction, ("%s / %s"):format(Format.short(stored), Format.short(capacity)))
	vaultCollect.setDisabled(stored < 1)
	local shieldLeft = baseState.ShieldUntil - serverNow()
	if shieldLeft > 0 then
		setShield("Shield " .. Format.duration(shieldLeft), true)
	else
		setShield("No shield", false)
	end
end

local function refreshLevel()
	if not baseState then
		return
	end
	local fraction = baseState.XPNeeded > 0 and baseState.XP / baseState.XPNeeded or 1
	setLevel(fraction, ("Base Lv %d"):format(baseState.Level))
	setLevelText(("%d / %d XP"):format(baseState.XP, baseState.XPNeeded))
	local unrevenged = 0
	for _, entry in baseState.RaidLog or {} do
		if not entry.revenged and entry.userId and entry.userId > 0 and entry.amount > 0 then
			unrevenged += 1
		end
	end
	raidLogBadge.set(unrevenged)
end

local function build()
	local layer = HudController.hudLayer()
	hubRoot = Make(
		"Frame",
		{ Name = "Hub", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = layer }
	)

	-- RAID button, bottom right
	raidButton = Components.Button({
		Name = "Raid",
		Text = "RAID!",
		TextSize = 30,
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Size = UDim2.new(0, 220, 0, 74),
		Position = UDim2.new(1, -24, 1, -24),
		Anchor = Vector2.new(1, 1),
		Radius = 37,
		Parent = hubRoot,
		OnClick = function()
			Net.Client.fire("RequestRaid", "Any")
		end,
	})
	local pulse = Make("UIScale", { Scale = 1, Parent = raidButton })
	pulseTween = TweenService:Create(
		pulse,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.06 }
	)
	pulseTween:Play()

	-- BUILD button, left of RAID
	Components.Button({
		Name = "Build",
		Text = "BUILD",
		TextSize = 22,
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Size = UDim2.new(0, 150, 0, 58),
		Position = UDim2.new(1, -260, 1, -32),
		Anchor = Vector2.new(1, 1),
		Radius = 29,
		Parent = hubRoot,
		OnClick = function()
			HubController.BuildRequested:Fire()
		end,
	})

	Components.Button({
		Name = "Home",
		Text = "HOME",
		TextSize = 18,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0, 110, 0, 46),
		Position = UDim2.new(1, -426, 1, -38),
		Anchor = Vector2.new(1, 1),
		Radius = 23,
		Parent = hubRoot,
		OnClick = function()
			Net.Client.fire("GoHome")
		end,
	})

	-- Vault card, top right
	local card = Components.Panel({
		Name = "VaultCard",
		Size = UDim2.new(0, 250, 0, 118),
		Position = UDim2.new(1, -16, 0, 12),
		Anchor = Vector2.new(1, 0),
		Parent = hubRoot,
	})
	Components.Text({
		Text = "VAULT",
		Font = Theme.Fonts.Display,
		TextSize = 16,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = card,
	})
	local _, vaultSetter = Components.ProgressBar({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 24),
		Color = Theme.Colors.Coin,
		Value = 0,
		Label = "0 / 0",
		Parent = card,
	})
	setVault = vaultSetter
	local collectButton, collectApi = Components.Button({
		Name = "Collect",
		Text = "COLLECT",
		TextSize = 16,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0.55, 0, 0, 36),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = card,
		OnClick = function()
			Net.Client.fire("CollectVault")
			EffectsController.sound("Coin", 0.6)
		end,
	})
	local _ = collectButton
	vaultCollect = collectApi
	local shieldLabel = Components.Text({
		Text = "No shield",
		Size = UDim2.new(0.42, 0, 0, 36),
		Position = UDim2.new(1, 0, 1, 0),
		Anchor = Vector2.new(1, 1),
		Align = Enum.TextXAlignment.Right,
		TextSize = 14,
		Font = Theme.Fonts.Bold,
		Color = Theme.Colors.TextMuted,
		Parent = card,
	})
	setShield = function(text, active)
		shieldLabel.Text = text
		shieldLabel.TextColor3 = active and Theme.Colors.Accent or Theme.Colors.TextMuted
	end

	-- Level bar, top centre
	local levelFrame = Make("Frame", {
		Name = "Level",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 300, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = hubRoot,
	})
	local _, levelSetter = Components.ProgressBar({
		Size = UDim2.new(1, 0, 0, 24),
		Color = Theme.Colors.Accent,
		Value = 0,
		Label = "Base Lv 1",
		Parent = levelFrame,
	})
	setLevel = levelSetter
	local xpText = Components.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 0, 25),
		Align = Enum.TextXAlignment.Center,
		TextSize = 12,
		Color = Theme.Colors.TextMuted,
		Parent = levelFrame,
	})
	setLevelText = function(text)
		xpText.Text = text
	end

	-- Side menu entries
	local logButton = HudController.addMenuButton({
		Name = "RaidLog",
		Text = "Raids",
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Order = 1,
		Screen = "RaidLog",
	})
	local badge, setBadge = Components.Badge({
		Text = "0",
		Position = UDim2.new(1, 4, 0, -4),
		Anchor = Vector2.new(1, 0),
		Parent = logButton,
	})
	badge.Visible = false
	raidLogBadge = {
		set = function(n)
			badge.Visible = n > 0
			setBadge(tostring(n))
		end,
	}
	HudController.addMenuButton({
		Name = "Shop",
		Text = "Shop",
		Color = Theme.Colors.Gem,
		ColorDark = Theme.Colors.GemDark,
		Order = 2,
		Screen = "Shop",
	})
	HudController.addMenuButton({
		Name = "Base",
		Text = "Gear",
		Color = Theme.Colors.Primary,
		ColorDark = Theme.Colors.PrimaryDark,
		Order = 3,
		Screen = "Base",
	})
	HudController.addMenuButton({
		Name = "League",
		Text = "League",
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Order = 4,
		Screen = "League",
	})
	HudController.addMenuButton({
		Name = "Quests",
		Text = "Quests",
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Order = 5,
		Screen = "Quests",
	})
	HudController.addMenuButton({
		Name = "Settings",
		Text = "More",
		Color = Theme.Colors.Stroke,
		ColorDark = Theme.Colors.Background,
		Order = 6,
		Screen = "Settings",
	})
end

-- Prompts on the plaza portal and shop stall.
local function setupPrompts()
	local map = workspace:WaitForChild("Map", 20)
	local plaza = map and map:WaitForChild("Plaza", 20)
	if not plaza then
		return
	end
	local portal = plaza:FindFirstChild("PortalDisc")
	if portal then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Raid"
		prompt.ObjectText = "Raid Portal"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = portal
		prompt.Triggered:Connect(function()
			Net.Client.fire("RequestRaid", "Any")
		end)
	end
	local stall = plaza:FindFirstChild("StallSign")
	if stall then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Shop"
		prompt.ObjectText = "Gem Stall"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = stall
		prompt.Triggered:Connect(function()
			HudController.open("Shop")
		end)
	end
	-- Plot signs show owner names.
	local plots = map:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local sign = plot:FindFirstChild("Sign")
			if sign then
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Front
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 40
				gui.Parent = sign
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.FontFace = Theme.Fonts.Display
				label.TextScaled = true
				label.TextColor3 = Color3.fromRGB(255, 230, 170)
				label.TextStrokeTransparency = 0.4
				label.Text = "FOR SALE"
				label.Parent = gui
				local function refresh()
					local name = sign:GetAttribute("OwnerName")
					label.Text = name and (name .. "'s Base") or "EMPTY PLOT"
				end
				sign:GetAttributeChangedSignal("OwnerName"):Connect(refresh)
				refresh()
			end
		end
	end
end

function HubController.setRaiding(state: boolean)
	raiding = state
	hubRoot.Visible = not state and not buildMode
	HudController.hudLayer():FindFirstChild("SideMenu").Visible = not state and not buildMode
	HudController.hudLayer():FindFirstChild("Currencies").Visible = not state
	HubController.RaidingChanged:Fire(state)
end

function HubController.setBuildMode(state: boolean)
	buildMode = state
	hubRoot.Visible = not state and not raiding
	HudController.hudLayer():FindFirstChild("SideMenu").Visible = not state and not raiding
end

function HubController.baseState()
	return baseState
end

HubController.BuildRequested = Signal.new()

function HubController.init()
	build()
	task.spawn(setupPrompts)

	Net.Client.on("BaseState", function(state)
		state.ReceivedAt = os.clock()
		baseState = state
		ClientData.set("Base", state)
		refreshVault()
		refreshLevel()
		HubController.BaseChanged:Fire(state)
	end)
	Net.Client.on("VaultTick", function(stored, capacity, shieldUntil)
		if baseState then
			baseState.Stored = stored
			baseState.Capacity = capacity
			baseState.ShieldUntil = shieldUntil
			refreshVault()
		end
	end)
	Net.Client.on("LevelUp", function(level)
		HudController.toast(("BASE LEVEL %d! New pieces unlocked."):format(level), "success", 3.5)
		EffectsController.sound("Win", 0.7)
	end)
	Net.Client.on("BuildError", function(reason)
		HudController.toast(tostring(reason), "warn", 2)
	end)
	Net.Client.on("RaidError", function(reason)
		HudController.toast(tostring(reason), "warn", 2.5)
	end)
	Net.Client.on("RaidAlert", function(info)
		if info.amount and info.amount > 0 then
			HudController.toast(
				("%s raided you and took %s coins!"):format(info.name, Format.short(info.amount)),
				"danger",
				4
			)
			EffectsController.sound("Alarm", 0.6)
			EffectsController.shake(0.6)
		else
			HudController.toast(("%s raided you and got NOTHING. Nice base."):format(info.name), "success", 4)
		end
	end)

	-- Keep shield countdown ticking.
	task.spawn(function()
		while true do
			task.wait(1)
			if baseState and hubRoot.Visible then
				refreshVault()
			end
		end
	end)

	-- Ask for the state in case we booted after the server pushed it.
	task.delay(1.5, function()
		if not baseState then
			local state = Net.Client.invoke("RequestBaseState")
			if state and not baseState then
				state.ReceivedAt = os.clock()
				baseState = state
				ClientData.set("Base", state)
				refreshVault()
				refreshLevel()
				HubController.BaseChanged:Fire(state)
			end
		end
	end)

	local _ = Players
end

return HubController
