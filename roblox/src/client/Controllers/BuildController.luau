--!nonstrict
-- BuildController: build mode on the player's own plot.
-- Pick a piece, drag the ghost over the grid, tap to place; tap a placed piece to upgrade, move
-- or sell. Works with mouse, touch and gamepad. The server validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Pieces = require(Shared.Data.Pieces)
local Themes = require(Shared.Data.Themes)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net.Net)
local Grid = require(Shared.Grid)
local BaseLayout = require(Shared.BaseLayout)
local RaidRules = require(Shared.RaidRules)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local ClientData = require(script.Parent.ClientData)
local HudController = require(script.Parent.HudController)
local HubController = require(script.Parent.HubController)
local InputController = require(script.Parent.InputController)
local EffectsController = require(script.Parent.EffectsController)

local BuildController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local active = false
local plot: Model? = nil
local plotRoot: CFrame? = nil
local root = nil -- UI root
local bar, cardsFrame, slotLabel, hintLabel, placeButton, infoPanel
local selectedId: string? = nil
local ghost: Model? = nil
local ghostHighlight: Highlight? = nil
local ghostCell = { x = 0, z = 0, r = 0, ok = false }
local movingIndex: number? = nil
local selectedIndex: number? = nil
local connections = {}
local gridLines = nil
local category = "Wall"

local CATEGORIES = {
	{ key = "Wall", label = "Walls" },
	{ key = "Trap", label = "Traps" },
	{ key = "Turret", label = "Turrets" },
	{ key = "Guard", label = "Guards" },
	{ key = "Structure", label = "Mines" },
	{ key = "Decor", label = "Decor" },
}

local function baseState()
	return HubController.baseState()
end

local function layout()
	local state = baseState()
	return state and state.Layout or {}
end

local function baseLevel(): number
	local state = baseState()
	return state and state.Level or 1
end

------------------------------------------------------------------------------------------------
-- Ghost
------------------------------------------------------------------------------------------------

local function clearGhost()
	local g = ghost
	ghost = nil
	ghostHighlight = nil
	if g then
		g:Destroy()
	end
end

local function makeGhost(id: string)
	clearGhost()
	local template = ReplicatedStorage.Assets.Pieces:FindFirstChild(id)
	if not template then
		return
	end
	local g = template:Clone()
	g.Name = "Ghost"
	for _, descendant in g:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Transparency = math.max(descendant.Transparency, 0.45)
		elseif descendant:IsA("PointLight") then
			descendant:Destroy()
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.Parent = g
	g.Parent = workspace
	ghost = g
	ghostHighlight = highlight
end

local function updateGhost()
	local g, highlight, id, rootCf = ghost, ghostHighlight, selectedId, plotRoot
	if not g or not id or not rootCf then
		return
	end
	local def = Pieces.get(id)
	local cx, cz = Grid.localOffset(ghostCell.x, ghostCell.z, def.size.w, def.size.d, ghostCell.r)
	g:PivotTo(rootCf * CFrame.new(cx, 1.0, cz) * CFrame.Angles(0, Grid.angle(ghostCell.r), 0))
	local ok =
		BaseLayout.canPlace(layout(), id, ghostCell.x, ghostCell.z, ghostCell.r, baseLevel(), movingIndex)
	ghostCell.ok = ok
	if highlight then
		highlight.FillColor = ok and Theme.Colors.Success or Theme.Colors.Danger
		highlight.OutlineColor = ok and Theme.Colors.Success or Theme.Colors.Danger
	end
	if placeButton then
		placeButton.setDisabled(not ok)
	end
end

-- Raycast the screen position onto the plot's ground plane and snap to the grid.
local function cellFromScreen(screenX: number, screenY: number): (number?, number?)
	if not plotRoot or not selectedId then
		return nil, nil
	end
	local ray = camera:ViewportPointToRay(screenX, screenY)
	local planeY = plotRoot.Position.Y + 1.0
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil, nil
	end
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil, nil
	end
	local hit = ray.Origin + ray.Direction * t
	local localPos = plotRoot:PointToObjectSpace(hit)
	local def = Pieces.get(selectedId)
	return Grid.snap(localPos.X, localPos.Z, def.size.w, def.size.d, ghostCell.r)
end

local function pieceAtScreen(screenX: number, screenY: number): number?
	if not plot then
		return nil
	end
	local base = plot:FindFirstChild("Base")
	if not base then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenX, screenY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { base }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not result then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	while model and model:GetAttribute("PieceIndex") == nil do
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return model and model:GetAttribute("PieceIndex") or nil
end

------------------------------------------------------------------------------------------------
-- Grid overlay
------------------------------------------------------------------------------------------------

local function showGrid()
	if gridLines or not plotRoot then
		return
	end
	gridLines = Instance.new("Model")
	gridLines.Name = "GridLines"
	local size = Grid.Studs
	for i = 0, Grid.Size do
		local offset = -size / 2 + i * Grid.Cell
		for axis = 1, 2 do
			local line = Instance.new("Part")
			line.Anchored = true
			line.CanCollide = false
			line.CanQuery = false
			line.CanTouch = false
			line.Material = Enum.Material.Neon
			line.Color = Color3.fromRGB(255, 255, 255)
			line.Transparency = 0.75
			line.Size = axis == 1 and Vector3.new(0.15, 0.05, size) or Vector3.new(size, 0.05, 0.15)
			line.CFrame = plotRoot * CFrame.new(axis == 1 and offset or 0, 1.06, axis == 2 and offset or 0)
			line.Parent = gridLines
		end
	end
	-- Entrance strip
	local e = Balance.Grid.Entrance
	local ex, ez = Grid.entranceLocal()
	local strip = Instance.new("Part")
	strip.Anchored = true
	strip.CanCollide = false
	strip.CanQuery = false
	strip.Material = Enum.Material.Neon
	strip.Color = Theme.Colors.Danger
	strip.Transparency = 0.7
	strip.Size = Vector3.new((e.x1 - e.x0 + 1) * Grid.Cell, 0.05, (e.z1 - e.z0 + 1) * Grid.Cell)
	strip.CFrame = plotRoot * CFrame.new(ex, 1.07, ez)
	strip.Parent = gridLines
	gridLines.Parent = workspace
end

local function hideGrid()
	if gridLines then
		gridLines:Destroy()
		gridLines = nil
	end
end

------------------------------------------------------------------------------------------------
-- Piece cards
------------------------------------------------------------------------------------------------

local function refreshSlots()
	local counts = BaseLayout.counts(layout())
	local key = category == "Structure" and "Mine" or category
	local used = counts[key] or 0
	local total = Pieces.slots(key, baseLevel())
	slotLabel.Text = ("%s: %d / %d slots"):format(key == "Mine" and "Mines" or category, used, total)
end

local function select(id: string?)
	selectedId = id
	movingIndex = nil
	if id then
		makeGhost(id)
		hintLabel.Text = InputController.isTouch()
				and "Drag on the grid, then tap PLACE. Tap a placed piece to upgrade it."
			or "Click on the grid to place. R rotates. Click a placed piece to upgrade it."
		updateGhost()
	else
		clearGhost()
		hintLabel.Text = "Pick a piece below, or tap a placed piece."
	end
	if infoPanel then
		infoPanel.Visible = false
	end
	for _, card in cardsFrame:GetChildren() do
		if card:IsA("TextButton") then
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = card.Name == ("Card_" .. tostring(id)) and Theme.Colors.Text
					or Theme.Colors.Stroke
				stroke.Thickness = card.Name == ("Card_" .. tostring(id)) and 4 or 2
			end
		end
	end
end

local function buildCards()
	for _, child in cardsFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local level = baseLevel()
	local coins = ClientData.get("Coins") or 0
	local list = Pieces.ByCategory[category] or {}
	for order, def in list do
		if def.id == "Vault" then
			continue
		end
		local locked = def.unlock > level
		local card = Make("TextButton", {
			Name = "Card_" .. def.id,
			Size = UDim2.new(0, 132, 1, 0),
			BackgroundColor3 = locked and Theme.Colors.Background or Theme.Colors.PanelLight,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = order,
			Parent = cardsFrame,
			[1] = Components.corner(12),
			[2] = Components.stroke(Theme.Colors.Stroke, 2),
			[3] = Make(
				"UIPadding",
				{ PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }
			),
		})
		Components.Text({
			Text = def.name,
			Font = Theme.Fonts.Display,
			TextSize = 16,
			Size = UDim2.new(1, 0, 0, 20),
			Parent = card,
		})
		Components.Text({
			Text = locked and ("Unlocks at Lv " .. def.unlock) or def.description,
			TextSize = 11,
			Color = Theme.Colors.TextMuted,
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.new(0, 0, 0, 20),
			VAlign = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local cost = Pieces.cost(def.id, 1)
		Components.Text({
			Text = locked and "LOCKED" or (Format.short(cost) .. " coins"),
			Font = Theme.Fonts.Display,
			TextSize = 15,
			Color = locked and Theme.Colors.Danger
				or (coins >= cost and Theme.Colors.Coin or Theme.Colors.Danger),
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.new(0, 0, 1, -24),
			Parent = card,
		})
		card.Activated:Connect(function()
			if locked then
				HudController.toast(("Reach base level %d to unlock %s"):format(def.unlock, def.name), "warn")
				return
			end
			select(def.id)
		end)
	end
	refreshSlots()
end

local function setCategory(key: string)
	category = key
	for _, tab in bar:FindFirstChild("Tabs"):GetChildren() do
		if tab:IsA("TextButton") then
			tab.BackgroundColor3 = tab.Name == key and Theme.Colors.Accent or Theme.Colors.PanelLight
		end
	end
	select(nil)
	buildCards()
end

------------------------------------------------------------------------------------------------
-- Info panel for a placed piece
------------------------------------------------------------------------------------------------

local function showInfo(index: number)
	local piece = layout()[index]
	if not piece then
		return
	end
	selectedIndex = index
	select(nil)
	local def = Pieces.get(piece.id)
	infoPanel.Visible = true
	local title = infoPanel:FindFirstChild("Title")
	title.Text = ("%s  Lv %d"):format(def.name, piece.lvl)
	local body = infoPanel:FindFirstChild("Body")
	local pending = nil
	local state = baseState()
	for _, p in state.Pending or {} do
		if p.index == index then
			pending = p
		end
	end
	local statLine = ""
	if piece.id == "Mine" then
		statLine = ("%s coins/h"):format(Format.short(Pieces.stat("Mine", piece.lvl, "income")))
	elseif piece.id == "Vault" then
		statLine = ("Capacity %s"):format(Format.short(Pieces.stat("Vault", piece.lvl, "capacity")))
	else
		statLine = ("HP %s  Rating %d"):format(
			Format.short(Pieces.hp(piece.id, piece.lvl)),
			Pieces.rating(piece.id, piece.lvl)
		)
	end
	local upgradeText
	if pending then
		upgradeText = ("Upgrading to Lv %d: %s left"):format(
			pending.toLevel,
			Format.duration(pending.readyAt - os.time())
		)
	elseif piece.lvl >= def.maxLevel then
		upgradeText = "MAX LEVEL"
	else
		local seconds = RaidRules.upgradeSeconds(piece.lvl + 1)
		upgradeText = ("Upgrade: %s coins%s"):format(
			Format.short(Pieces.cost(piece.id, piece.lvl + 1)),
			seconds > 0 and (", " .. Format.duration(seconds)) or ""
		)
	end
	body.Text = statLine .. "\n" .. upgradeText
	local upgradeButton = infoPanel:FindFirstChild("Upgrade")
	local skipButton = infoPanel:FindFirstChild("Skip")
	local moveButton = infoPanel:FindFirstChild("Move")
	local sellButton = infoPanel:FindFirstChild("Sell")
	upgradeButton.Visible = not pending and piece.lvl < def.maxLevel
	skipButton.Visible = pending ~= nil
	if pending then
		skipButton:FindFirstChild("Content").Label.Text = ("SKIP (%d gems)"):format(
			RaidRules.skipGems(pending.readyAt - os.time())
		)
	end
	moveButton.Visible = true
	sellButton.Visible = def.sellable
	if def.sellable then
		sellButton:FindFirstChild("Content").Label.Text = ("SELL +%s"):format(
			Format.short(Pieces.refund(piece.id, piece.lvl))
		)
	end
end

local function startMove()
	local index = selectedIndex
	local piece = index and layout()[index]
	if not piece then
		return
	end
	selectedId = piece.id
	movingIndex = index
	ghostCell.r = piece.r
	ghostCell.x, ghostCell.z = piece.x, piece.z
	makeGhost(piece.id)
	infoPanel.Visible = false
	hintLabel.Text = "Choose a new spot, then place."
	updateGhost()
end

------------------------------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------------------------------

local function tryPlace()
	if not selectedId or not ghostCell.ok then
		return
	end
	if movingIndex then
		Net.Client.fire("MovePiece", movingIndex, ghostCell.x, ghostCell.z, ghostCell.r)
		EffectsController.sound("Place", 0.5)
		select(nil)
		return
	end
	Net.Client.fire("PlacePiece", selectedId, ghostCell.x, ghostCell.z, ghostCell.r)
	EffectsController.sound("Place", 0.5)
	-- Keep the same piece selected for rapid wall building.
	task.delay(0.1, updateGhost)
end

local function rotate()
	ghostCell.r = (ghostCell.r + 1) % 4
	if selectedId then
		local def = Pieces.get(selectedId)
		local fw, fd = Grid.footprintSize(def.size.w, def.size.d, ghostCell.r)
		ghostCell.x = math.clamp(ghostCell.x, 0, Grid.Size - fw)
		ghostCell.z = math.clamp(ghostCell.z, 0, Grid.Size - fd)
	end
	updateGhost()
end

local function pointerMoved(x: number, y: number)
	if not selectedId then
		return
	end
	local cx, cz = cellFromScreen(x, y)
	if cx then
		if cx ~= ghostCell.x or cz ~= ghostCell.z then
			ghostCell.x, ghostCell.z = cx, cz
			updateGhost()
		end
	end
end

local function pointerTapped(x: number, y: number)
	-- Ignore taps on UI.
	local guiObjects =
		player.PlayerGui:GetGuiObjectsAtPosition(x, y - game:GetService("GuiService"):GetGuiInset().Y)
	for _, obj in guiObjects do
		if obj:IsA("GuiButton") or obj.Name == "Panel" or obj.Name == "BuildBar" or obj.Name == "Info" then
			return
		end
	end
	if selectedId then
		pointerMoved(x, y)
		if InputController.isTouch() then
			return -- touch confirms with the PLACE button
		end
		tryPlace()
		return
	end
	local index = pieceAtScreen(x, y)
	if index then
		showInfo(index)
	else
		infoPanel.Visible = false
	end
end

local function bindInput()
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				pointerMoved(input.Position.X, input.Position.Y)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if not processed then
					pointerTapped(input.Position.X, input.Position.Y)
				end
			elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
				rotate()
			elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
				if selectedId then
					select(nil)
				else
					BuildController.exit()
				end
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				tryPlace()
			end
		end)
	)
end

------------------------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------------------------

local function buildUi()
	root = Make("Frame", {
		Name = "BuildUi",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = HudController.hudLayer(),
	})

	bar = Components.Panel({
		Name = "BuildBar",
		Size = UDim2.new(1, -32, 0, 176),
		Position = UDim2.new(0.5, 0, 1, -12),
		Anchor = Vector2.new(0.5, 1),
		Parent = root,
	})
	local tabs = Make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -200, 0, 32),
		Parent = bar,
		[1] = Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for order, entry in CATEGORIES do
		local tab = Make("TextButton", {
			Name = entry.key,
			Size = UDim2.new(0, 96, 1, 0),
			BackgroundColor3 = Theme.Colors.PanelLight,
			AutoButtonColor = false,
			Text = entry.label,
			TextColor3 = Theme.Colors.Text,
			FontFace = Theme.Fonts.Display,
			TextSize = 16,
			LayoutOrder = order,
			Parent = tabs,
			[1] = Components.corner(10),
		})
		tab.Activated:Connect(function()
			setCategory(entry.key)
		end)
	end
	slotLabel = Components.Text({
		Text = "",
		Size = UDim2.new(0, 190, 0, 32),
		Position = UDim2.new(1, 0, 0, 0),
		Anchor = Vector2.new(1, 0),
		Align = Enum.TextXAlignment.Right,
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		Color = Theme.Colors.TextMuted,
		Parent = bar,
	})
	cardsFrame = Make("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 96),
		Position = UDim2.new(0, 0, 0, 38),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		Parent = bar,
		[1] = Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	hintLabel = Components.Text({
		Text = "",
		Size = UDim2.new(1, -330, 0, 20),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
		Parent = bar,
	})

	local exitButton = Components.Button({
		Name = "Exit",
		Text = "DONE",
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0, 100, 0, 36),
		Position = UDim2.new(1, 0, 1, 0),
		Anchor = Vector2.new(1, 1),
		Parent = bar,
		OnClick = function()
			BuildController.exit()
		end,
	})
	local _ = exitButton
	Components.Button({
		Name = "Rotate",
		Text = "ROTATE",
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Size = UDim2.new(0, 100, 0, 36),
		Position = UDim2.new(1, -108, 1, 0),
		Anchor = Vector2.new(1, 1),
		Parent = bar,
		OnClick = rotate,
	})
	local placeBtn, placeApi = Components.Button({
		Name = "Place",
		Text = "PLACE",
		Color = Theme.Colors.Primary,
		ColorDark = Theme.Colors.PrimaryDark,
		Size = UDim2.new(0, 110, 0, 36),
		Position = UDim2.new(1, -216, 1, 0),
		Anchor = Vector2.new(1, 1),
		Parent = bar,
		OnClick = tryPlace,
	})
	placeButton = placeApi
	local _ = placeBtn

	infoPanel = Components.Panel({
		Name = "Info",
		Size = UDim2.new(0, 300, 0, 190),
		Position = UDim2.new(1, -16, 0, 60),
		Anchor = Vector2.new(1, 0),
		Title = "Piece",
		Parent = root,
	})
	infoPanel.Visible = false
	Components.Text({
		Name = "Body",
		Text = "",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 0, 40),
		TextSize = 14,
		Parent = infoPanel,
	})
	Components.Button({
		Name = "Upgrade",
		Text = "UPGRADE",
		Color = Theme.Colors.Primary,
		ColorDark = Theme.Colors.PrimaryDark,
		Size = UDim2.new(0.48, 0, 0, 36),
		Position = UDim2.new(0, 0, 1, -42),
		Parent = infoPanel,
		OnClick = function()
			if selectedIndex then
				Net.Client.fire("UpgradePiece", selectedIndex)
			end
		end,
	})
	Components.Button({
		Name = "Skip",
		Text = "SKIP",
		Color = Theme.Colors.Gem,
		ColorDark = Theme.Colors.GemDark,
		Size = UDim2.new(0.48, 0, 0, 36),
		Position = UDim2.new(0, 0, 1, -42),
		Parent = infoPanel,
		OnClick = function()
			if selectedIndex then
				Net.Client.fire("SkipUpgrade", selectedIndex)
			end
		end,
	})
	Components.Button({
		Name = "Move",
		Text = "MOVE",
		Color = Theme.Colors.Accent,
		ColorDark = Theme.Colors.AccentDark,
		Size = UDim2.new(0.48, 0, 0, 36),
		Position = UDim2.new(1, 0, 1, -42),
		Anchor = Vector2.new(1, 0),
		Parent = infoPanel,
		OnClick = startMove,
	})
	Components.Button({
		Name = "Sell",
		Text = "SELL",
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		TextSize = 14,
		Parent = infoPanel,
		OnClick = function()
			if selectedIndex then
				Net.Client.fire("SellPiece", selectedIndex)
				infoPanel.Visible = false
			end
		end,
	})
end

------------------------------------------------------------------------------------------------
-- Enter / exit
------------------------------------------------------------------------------------------------

local savedCameraType = nil

function BuildController.enter()
	local state = baseState()
	if active or not state or state.PlotIndex == nil then
		HudController.toast("Your plot is still loading.", "warn")
		return
	end
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
	local found = plots and plots:FindFirstChild("Plot" .. state.PlotIndex)
	if not found or not found:IsA("Model") or not found.PrimaryPart then
		return
	end
	plot = found
	local rootCf = found.PrimaryPart.CFrame
	plotRoot = rootCf
	active = true
	HudController.close()
	HubController.setBuildMode(true)
	root.Visible = true
	-- Camera: over the plot looking down at the base from the entrance side.
	savedCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local eye = rootCf * CFrame.new(0, 58, 60)
	TweenService:Create(camera, Theme.Anim.Slow, { CFrame = CFrame.lookAt(eye.Position, rootCf.Position) })
		:Play()
	-- Freeze the character in place.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.Anchored = true
	end
	showGrid()
	setCategory("Wall")
	bindInput()
	EffectsController.sound("Click", 0.5)
end

function BuildController.exit()
	if not active then
		return
	end
	active = false
	select(nil)
	hideGrid()
	root.Visible = false
	infoPanel.Visible = false
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	camera.CameraType = savedCameraType or Enum.CameraType.Custom
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.Anchored = false
	end
	HubController.setBuildMode(false)
end

function BuildController.toggle()
	if active then
		BuildController.exit()
	else
		BuildController.enter()
	end
end

function BuildController.isActive(): boolean
	return active
end

function BuildController.init()
	buildUi()
	HubController.BuildRequested:Connect(BuildController.toggle)
	HubController.BaseChanged:Connect(function()
		if active then
			buildCards()
			if selectedIndex and infoPanel.Visible then
				showInfo(selectedIndex)
			end
			updateGhost()
			-- Theme changes recolour the ghost too.
			if ghost and baseState() then
				for _, descendant in ghost:GetDescendants() do
					if descendant:IsA("BasePart") and descendant:GetAttribute("ThemeKey") then
						descendant.Color =
							Themes.color(baseState().Theme, descendant:GetAttribute("ThemeKey"))
					end
				end
			end
		end
	end)
	ClientData.Changed:Connect(function(key)
		if key == "Coins" and active then
			buildCards()
		end
	end)
	HubController.RaidingChanged:Connect(function(isRaiding)
		if isRaiding then
			BuildController.exit()
		end
	end)
	local _ = RunService
end

return BuildController
