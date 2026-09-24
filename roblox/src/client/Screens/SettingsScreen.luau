--!nonstrict
-- SettingsScreen ("More"): toggles, promo codes, links.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local ClientData = require(Controllers.ClientData)
local HudController = require(Controllers.HudController)

local SettingsScreen = {}

local toggles = {}
local codeBox, codeResult

local TOGGLES = {
	{ key = "Music", label = "Music" },
	{ key = "Sfx", label = "Sound effects" },
	{ key = "Shake", label = "Camera shake" },
}

local function refresh()
	local settings = ClientData.get("Settings") or {}
	for _, entry in TOGGLES do
		local api = toggles[entry.key]
		if api then
			local on = settings[entry.key] ~= false
			api.setText(on and "ON" or "OFF")
		end
	end
end

local function build()
	local frame, body =
		HudController.modal({ Name = "Settings", Size = UDim2.new(0, 520, 0, 400), Title = "SETTINGS" })
	local y = 0
	for _, entry in TOGGLES do
		Components.Text({
			Text = entry.label,
			TextSize = 16,
			Size = UDim2.new(0.6, 0, 0, 40),
			Position = UDim2.new(0, 0, 0, y),
			Parent = body,
		})
		local _, api = Components.Button({
			Text = "ON",
			TextSize = 15,
			Color = Theme.Colors.Accent,
			ColorDark = Theme.Colors.AccentDark,
			Size = UDim2.new(0, 100, 0, 36),
			Position = UDim2.new(1, 0, 0, y + 2),
			Anchor = Vector2.new(1, 0),
			Parent = body,
			OnClick = function()
				local settings = ClientData.get("Settings") or {}
				local newValue = settings[entry.key] == false
				settings[entry.key] = newValue
				ClientData.set("Settings", settings)
				Net.Client.fire("SetSetting", entry.key, newValue)
				refresh()
			end,
		})
		toggles[entry.key] = api
		y += 46
	end

	y += 12
	Components.Text({
		Text = "Promo code",
		Font = Theme.Fonts.Display,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, y),
		Parent = body,
	})
	codeBox = Make("TextBox", {
		Size = UDim2.new(0.6, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, y + 24),
		BackgroundColor3 = Theme.Colors.Background,
		PlaceholderText = "ENTER CODE",
		Text = "",
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Bold,
		TextSize = 16,
		ClearTextOnFocus = false,
		Parent = body,
		[1] = Components.corner(10),
		[2] = Components.padding(8),
	})
	Components.Button({
		Text = "REDEEM",
		TextSize = 15,
		Color = Theme.Colors.Success,
		ColorDark = Theme.Colors.SuccessDark,
		Size = UDim2.new(0, 130, 0, 40),
		Position = UDim2.new(0.6, 12, 0, y + 24),
		Parent = body,
		OnClick = function()
			Net.Client.fire("RedeemCode", codeBox.Text)
		end,
	})
	codeResult = Components.Text({
		Text = "",
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, y + 68),
		Parent = body,
	})
	Components.Text({
		Text = ("%s v%s  •  Like and favourite the game for free codes in updates."):format(
			GameConfig.GameName,
			GameConfig.Version
		),
		TextSize = 12,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = body,
	})
	return frame, { onOpen = refresh }
end

function SettingsScreen.register()
	HudController.registerScreen("Settings", build)
	Net.Client.on("CodeResult", function(ok, message)
		if codeResult then
			codeResult.Text = message
			codeResult.TextColor3 = ok and Theme.Colors.Success or Theme.Colors.Danger
		end
		HudController.toast(message, ok and "success" or "warn", 3)
		if ok and codeBox then
			codeBox.Text = ""
		end
	end)
end

return SettingsScreen
