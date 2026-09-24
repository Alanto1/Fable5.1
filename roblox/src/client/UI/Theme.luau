--!nonstrict
-- Theme: one place for colour, type and spacing so every screen reads as the same game.
-- Look: chunky toy-town. Deep navy backdrops, saturated accents, rounded everything, fat type.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(24, 27, 44),
	Panel = Color3.fromRGB(34, 38, 62),
	PanelLight = Color3.fromRGB(46, 51, 82),
	Stroke = Color3.fromRGB(70, 78, 120),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(170, 178, 210),
	TextDark = Color3.fromRGB(30, 26, 48),

	Primary = Color3.fromRGB(255, 176, 46), -- gold: loot, buttons of intent
	PrimaryDark = Color3.fromRGB(196, 124, 16),
	Accent = Color3.fromRGB(80, 200, 255), -- sky: info, raid
	AccentDark = Color3.fromRGB(28, 132, 190),
	Success = Color3.fromRGB(96, 224, 120),
	SuccessDark = Color3.fromRGB(44, 150, 70),
	Danger = Color3.fromRGB(255, 84, 96),
	DangerDark = Color3.fromRGB(170, 40, 52),
	Gem = Color3.fromRGB(186, 110, 255),
	GemDark = Color3.fromRGB(120, 60, 190),
	Coin = Color3.fromRGB(255, 205, 60),
	Robux = Color3.fromRGB(240, 240, 240),

	Rarity = {
		Common = Color3.fromRGB(190, 195, 210),
		Uncommon = Color3.fromRGB(96, 224, 120),
		Rare = Color3.fromRGB(80, 160, 255),
		Epic = Color3.fromRGB(186, 110, 255),
		Legendary = Color3.fromRGB(255, 176, 46),
		Mythic = Color3.fromRGB(255, 84, 160),
		Secret = Color3.fromRGB(40, 40, 50),
	},
}

Theme.Fonts = {
	Display = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.GothamMedium),
	Bold = Font.fromEnum(Enum.Font.GothamBold),
}

Theme.Sizes = {
	Radius = 14,
	RadiusSmall = 10,
	Stroke = 3,
	Padding = 12,
	Gap = 8,
	ButtonHeight = 52,
	IconButton = 64,
	TextSmall = 14,
	Text = 18,
	TextLarge = 24,
	Title = 34,
}

Theme.Anim = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

-- UI scale relative to a 1280x720 reference, clamped so phones stay readable and 4K stays sane.
function Theme.scaleFor(viewport: Vector2): number
	local byHeight = viewport.Y / 720
	local byWidth = viewport.X / 1280
	local scale = math.min(byHeight, byWidth)
	if viewport.Y < 500 then
		scale = math.max(scale, 0.78) -- phones: don't shrink below readable
	end
	return math.clamp(scale, 0.7, 1.6)
end

return Theme
