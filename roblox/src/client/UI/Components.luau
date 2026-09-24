--!nonstrict
-- Components: the reusable building blocks every screen is made of.
-- All components return the root Instance and take a props table; nothing here knows game rules.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Theme = require(script.Parent.Theme)
local Make = require(script.Parent.Make)

local Components = {}

local function corner(radius: number?)
	return Make("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Sizes.Radius) })
end

local function stroke(color: Color3?, thickness: number?)
	return Make("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or Theme.Sizes.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(all: number?)
	local p = UDim.new(0, all or Theme.Sizes.Padding)
	return Make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

Components.corner = corner
Components.stroke = stroke
Components.padding = padding

local clickSound = nil
local function playClick()
	if not clickSound then
		clickSound =
			Make("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.35, Parent = SoundService })
	end
	pcall(function()
		clickSound:Play()
	end)
end

-- Props: Text, Color, ColorDark, Size, Position, Anchor, Parent, OnClick, Icon (asset id), TextSize, Disabled
function Components.Button(props)
	local color = props.Color or Theme.Colors.Primary
	local colorDark = props.ColorDark or Theme.Colors.PrimaryDark
	local button = Make("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.new(0, 180, 0, Theme.Sizes.ButtonHeight),
		Position = props.Position or UDim2.new(0, 0, 0, 0),
		AnchorPoint = props.Anchor or Vector2.new(0, 0),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
		[1] = corner(props.Radius),
		[2] = stroke(colorDark, props.StrokeThickness),
		[3] = Make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 215, 215)),
			}),
			Rotation = 90,
		}),
	})

	local content = Make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = button.ZIndex + 1,
		Parent = button,
		[1] = Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	if props.Icon then
		Make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = props.Icon,
			Size = UDim2.new(
				0,
				(props.TextSize or Theme.Sizes.Text) * 1.4,
				0,
				(props.TextSize or Theme.Sizes.Text) * 1.4
			),
			LayoutOrder = 1,
			ZIndex = content.ZIndex,
			Parent = content,
		})
	end

	local label = Make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Text = props.Text or "",
		TextColor3 = props.TextColor or Theme.Colors.Text,
		TextSize = props.TextSize or Theme.Sizes.Text,
		FontFace = Theme.Fonts.Display,
		LayoutOrder = 2,
		ZIndex = content.ZIndex,
		Parent = content,
		[1] = Make("UIStroke", {
			Color = Theme.Colors.TextDark,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Transparency = 0.35,
		}),
	})

	local scale = Make("UIScale", { Scale = 1, Parent = button })
	local disabled = props.Disabled == true

	local function setDisabled(state: boolean)
		disabled = state
		button.BackgroundColor3 = state and Theme.Colors.Stroke or color
		label.TextTransparency = state and 0.4 or 0
	end
	setDisabled(disabled)

	button.MouseButton1Down:Connect(function()
		if disabled then
			return
		end
		TweenService:Create(scale, Theme.Anim.Fast, { Scale = 0.94 }):Play()
	end)
	local function release()
		TweenService:Create(scale, Theme.Anim.Pop, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		if disabled then
			return
		end
		playClick()
		if props.OnClick then
			props.OnClick(button)
		end
	end)

	return button,
		{
			setText = function(text)
				label.Text = text
			end,
			setDisabled = setDisabled,
			label = label,
		}
end

-- Props: Size, Position, Anchor, Parent, Title?, Color?, ZIndex?
function Components.Panel(props)
	local panel = Make("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size or UDim2.new(0, 400, 0, 300),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.Anchor or Vector2.new(0.5, 0.5),
		BackgroundColor3 = props.Color or Theme.Colors.Panel,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
		[1] = corner(),
		[2] = stroke(),
		[3] = padding(),
	})
	if props.Title then
		Make("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.Sizes.Title),
			Text = props.Title,
			TextColor3 = Theme.Colors.Text,
			TextSize = Theme.Sizes.TextLarge,
			FontFace = Theme.Fonts.Display,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = panel.ZIndex + 1,
			Parent = panel,
			[1] = Make("UIStroke", { Color = Theme.Colors.TextDark, Thickness = 2, Transparency = 0.4 }),
		})
	end
	return panel
end

-- Props: Text, Size, Position, Parent, TextSize, Color, Font, Align, Wrap, ZIndex, Name, Anchor
function Components.Text(props)
	return Make("TextLabel", {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, Theme.Sizes.Text + 6),
		Position = props.Position or UDim2.new(0, 0, 0, 0),
		AnchorPoint = props.Anchor or Vector2.new(0, 0),
		AutomaticSize = props.AutoSize or Enum.AutomaticSize.None,
		Text = props.Text or "",
		TextColor3 = props.Color or Theme.Colors.Text,
		TextSize = props.TextSize or Theme.Sizes.Text,
		FontFace = props.Font or Theme.Fonts.Body,
		TextXAlignment = props.Align or Enum.TextXAlignment.Left,
		TextYAlignment = props.VAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap ~= false,
		RichText = props.Rich == true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
end

-- A pill showing an icon and a number (currencies). Returns pill, setter.
function Components.Pill(props)
	local pill = Make("Frame", {
		Name = props.Name or "Pill",
		Size = props.Size or UDim2.new(0, 150, 0, 40),
		Position = props.Position,
		AnchorPoint = props.Anchor or Vector2.new(0, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
		[1] = corner(20),
		[2] = stroke(props.Color or Theme.Colors.Stroke, 2),
	})
	Make("Frame", {
		Name = "Dot",
		Size = UDim2.new(0, 26, 0, 26),
		Position = UDim2.new(0, 7, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = props.Color or Theme.Colors.Coin,
		ZIndex = pill.ZIndex + 1,
		Parent = pill,
		[1] = corner(13),
		[2] = Make("UIStroke", { Color = Theme.Colors.TextDark, Thickness = 2, Transparency = 0.5 }),
	})
	local value = Components.Text({
		Name = "Value",
		Text = props.Text or "0",
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.new(0, 40, 0, 0),
		Font = Theme.Fonts.Display,
		TextSize = props.TextSize or Theme.Sizes.Text,
		ZIndex = pill.ZIndex + 1,
		Parent = pill,
	})
	if props.OnClick then
		local hit = Make("TextButton", {
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = pill.ZIndex + 2,
			Parent = pill,
		})
		hit.Activated:Connect(function()
			playClick()
			props.OnClick()
		end)
	end
	return pill, function(text)
		value.Text = text
	end
end

-- Props: Size, Position, Parent, Color, Value (0..1), ZIndex, Label?
function Components.ProgressBar(props)
	local bar = Make("Frame", {
		Name = props.Name or "ProgressBar",
		Size = props.Size or UDim2.new(1, 0, 0, 18),
		Position = props.Position,
		AnchorPoint = props.Anchor or Vector2.new(0, 0),
		BackgroundColor3 = Theme.Colors.Background,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
		[1] = corner(9),
		[2] = stroke(Theme.Colors.Stroke, 2),
	})
	local fill = Make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(math.clamp(props.Value or 0, 0, 1), 1),
		BackgroundColor3 = props.Color or Theme.Colors.Success,
		ZIndex = bar.ZIndex + 1,
		Parent = bar,
		[1] = corner(9),
	})
	local label = nil
	if props.Label then
		label = Components.Text({
			Text = props.Label,
			Size = UDim2.fromScale(1, 1),
			Align = Enum.TextXAlignment.Center,
			TextSize = Theme.Sizes.TextSmall,
			Font = Theme.Fonts.Bold,
			ZIndex = bar.ZIndex + 2,
			Parent = bar,
		})
	end
	return bar,
		function(value: number, text: string?)
			TweenService:Create(fill, Theme.Anim.Fast, { Size = UDim2.fromScale(math.clamp(value, 0, 1), 1) })
				:Play()
			if label and text then
				label.Text = text
			end
		end
end

-- Round icon button used for the side menu. Props: Icon, Color, ColorDark, Text?, OnClick, Parent, Size
function Components.IconButton(props)
	local size = props.Size or Theme.Sizes.IconButton
	local button = Components.Button({
		Name = props.Name or "IconButton",
		Text = "",
		Icon = props.Icon,
		Color = props.Color or Theme.Colors.Accent,
		ColorDark = props.ColorDark or Theme.Colors.AccentDark,
		Size = UDim2.new(0, size, 0, size),
		Radius = size / 2,
		OnClick = props.OnClick,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	})
	if props.Text then
		Components.Text({
			Name = "Caption",
			Text = props.Text,
			Size = UDim2.new(1.6, 0, 0, 16),
			Position = UDim2.new(0.5, 0, 1, 2),
			Anchor = Vector2.new(0.5, 0),
			Align = Enum.TextXAlignment.Center,
			TextSize = 13,
			Font = Theme.Fonts.Bold,
			ZIndex = button.ZIndex + 1,
			Parent = button,
			[1] = Make("UIStroke", { Color = Theme.Colors.TextDark, Thickness = 2 }),
		})
	end
	return button
end

-- Badge: small rounded label, used for counts/rarity tags.
function Components.Badge(props)
	local badge = Make("Frame", {
		Name = props.Name or "Badge",
		Size = props.Size or UDim2.new(0, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position,
		AnchorPoint = props.Anchor or Vector2.new(0, 0),
		BackgroundColor3 = props.Color or Theme.Colors.Danger,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 5,
		Parent = props.Parent,
		[1] = corner(11),
		[2] = Make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	local text = Components.Text({
		Text = props.Text or "",
		Size = UDim2.new(0, 0, 1, 0),
		AutoSize = Enum.AutomaticSize.X,
		TextSize = 13,
		Font = Theme.Fonts.Bold,
		ZIndex = badge.ZIndex + 1,
		Parent = badge,
	})
	return badge, function(value)
		text.Text = value
	end
end

return Components
