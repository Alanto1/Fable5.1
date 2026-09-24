--!nonstrict
-- BaseScreen ("Gear"): raider gear upgrades, base name, personal stats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Format = require(Shared.Util.Format)
local RaidRules = require(Shared.RaidRules)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local ClientData = require(Controllers.ClientData)
local HudController = require(Controllers.HudController)
local HubController = require(Controllers.HubController)

local BaseScreen = {}

local rows = {}
local nameBox
local statsLabel

local GEAR = {
	{
		key = "Hammer",
		title = "Hammer",
		stat = function(level)
			return ("%d damage per swing"):format(RaidRules.hammerDamage(level))
		end,
		max = Balance.Gear.Hammer.MaxLevel,
	},
	{
		key = "Sack",
		title = "Loot Sack",
		stat = function(level)
			return ("holds %s coins"):format(Format.short(RaidRules.sackCapacity(level)))
		end,
		max = Balance.Gear.Sack.MaxLevel,
	},
	{
		key = "Boots",
		title = "Boots",
		stat = function(level)
			return ("%d%% less slowdown when heavy"):format(math.floor(RaidRules.bootsRelief(level) * 100))
		end,
		max = Balance.Gear.Boots.MaxLevel,
	},
}

local function refresh()
	local state = HubController.baseState()
	if not state then
		return
	end
	local coins = ClientData.get("Coins") or 0
	for _, gear in GEAR do
		local row = rows[gear.key]
		local level = state.Raider[gear.key]
		row.level.Text = ("%s  Lv %d"):format(gear.title, level)
		row.stat.Text = gear.stat(level)
		if level >= gear.max then
			row.button.setText("MAX")
			row.button.setDisabled(true)
		else
			local cost = RaidRules.gearCost(level + 1)
			row.button.setText(("UPGRADE  %s"):format(Format.short(cost)))
			row.button.setDisabled(coins < cost)
			row.next.Text = "Next: " .. gear.stat(level + 1)
		end
	end
	if nameBox and not nameBox:IsFocused() then
		nameBox.Text = state.Name ~= "" and state.Name or ""
	end
	local league = RaidRules.leagueFor(state.Raider.Trophies)
	statsLabel.Text = ("Trophies %d (%s league)   •   Defense rating %d   •   Income %s/h"):format(
		state.Raider.Trophies,
		league.name,
		state.Rating,
		Format.short(state.Income)
	)
end

local function build()
	local frame, body =
		HudController.modal({ Name = "Base", Size = UDim2.new(0, 640, 0, 460), Title = "GEAR & BASE" })
	local y = 0
	for _, gear in GEAR do
		local row = Make("Frame", {
			Name = gear.key,
			Size = UDim2.new(1, 0, 0, 84),
			Position = UDim2.new(0, 0, 0, y),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Parent = body,
			[1] = Components.corner(12),
			[2] = Components.padding(10),
		})
		local levelLabel = Components.Text({
			Text = gear.title,
			Font = Theme.Fonts.Display,
			TextSize = 20,
			Size = UDim2.new(0.6, 0, 0, 24),
			Parent = row,
		})
		local statLabel = Components.Text({
			Text = "",
			TextSize = 14,
			Color = Theme.Colors.TextMuted,
			Size = UDim2.new(0.6, 0, 0, 18),
			Position = UDim2.new(0, 0, 0, 26),
			Parent = row,
		})
		local nextLabel = Components.Text({
			Text = "",
			TextSize = 12,
			Color = Theme.Colors.Accent,
			Size = UDim2.new(0.6, 0, 0, 16),
			Position = UDim2.new(0, 0, 0, 44),
			Parent = row,
		})
		local _, api = Components.Button({
			Text = "UPGRADE",
			TextSize = 16,
			Color = Theme.Colors.Primary,
			ColorDark = Theme.Colors.PrimaryDark,
			Size = UDim2.new(0, 190, 0, 44),
			Position = UDim2.new(1, 0, 0.5, 0),
			Anchor = Vector2.new(1, 0.5),
			Parent = row,
			OnClick = function()
				Net.Client.fire("UpgradeGear", gear.key)
			end,
		})
		rows[gear.key] = { level = levelLabel, stat = statLabel, next = nextLabel, button = api }
		y += 92
	end

	Components.Text({
		Text = "Base name",
		Font = Theme.Fonts.Display,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, y),
		Parent = body,
	})
	nameBox = Make("TextBox", {
		Size = UDim2.new(0.6, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, y + 24),
		BackgroundColor3 = Theme.Colors.Background,
		PlaceholderText = "Name your base",
		Text = "",
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Body,
		TextSize = 16,
		ClearTextOnFocus = false,
		Parent = body,
		[1] = Components.corner(10),
		[2] = Components.padding(8),
	})
	Components.Button({
		Text = "SAVE",
		TextSize = 15,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0, 120, 0, 40),
		Position = UDim2.new(0.6, 12, 0, y + 24),
		Parent = body,
		OnClick = function()
			Net.Client.fire("RenameBase", nameBox.Text)
		end,
	})
	statsLabel = Components.Text({
		Text = "",
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = body,
	})
	return frame, { onOpen = refresh }
end

function BaseScreen.register()
	HudController.registerScreen("Base", build)
	HubController.BaseChanged:Connect(function()
		if HudController.isOpen("Base") then
			refresh()
		end
	end)
	ClientData.Changed:Connect(function(key)
		if key == "Coins" and HudController.isOpen("Base") then
			refresh()
		end
	end)
end

return BaseScreen
