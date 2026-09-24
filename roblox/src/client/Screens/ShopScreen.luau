--!nonstrict
-- ShopScreen: gems, passes, boosts and cosmetics.

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Data.Products)
local Cosmetics = require(Shared.Data.Cosmetics)
local Themes = require(Shared.Data.Themes)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local ClientData = require(Controllers.ClientData)
local HudController = require(Controllers.HudController)

local ShopScreen = {}

local TABS = { "Gems", "Passes", "Boosts", "Hammers", "Sacks", "Trails", "Themes" }

local frame, body, tabsFrame, listFrame
local currentTab = "Gems"
local cosmetics = nil

local function card(
	parent,
	order,
	title,
	subtitle,
	priceText,
	priceColor,
	buttonText,
	buttonColor,
	buttonDark,
	onClick,
	owned
)
	local c = Make("Frame", {
		Name = "Card",
		Size = UDim2.new(0, 200, 0, 150),
		BackgroundColor3 = Theme.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
		[1] = Components.corner(12),
		[2] = Components.stroke(owned and Theme.Colors.Success or Theme.Colors.Stroke, 2),
		[3] = Components.padding(10),
	})
	Components.Text({
		Text = title,
		Font = Theme.Fonts.Display,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = c,
	})
	Components.Text({
		Text = subtitle,
		TextSize = 12,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.new(0, 0, 0, 26),
		VAlign = Enum.TextYAlignment.Top,
		Parent = c,
	})
	Components.Text({
		Text = priceText,
		Font = Theme.Fonts.Display,
		TextSize = 16,
		Color = priceColor,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -62),
		Parent = c,
	})
	Components.Button({
		Text = buttonText,
		TextSize = 15,
		Color = buttonColor,
		ColorDark = buttonDark,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 1, 0),
		Anchor = Vector2.new(0, 1),
		Parent = c,
		OnClick = onClick,
	})
	return c
end

local function clearList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function fillGems()
	local order = 0
	for _, key in { "StarterPack", "Gems100", "Gems550", "Gems1200", "Gems3250", "Gems7000" } do
		local product = Products.DevProducts[key]
		order += 1
		local sub = product.gems
				and (product.gems .. " gems" .. (product.coins and (" + " .. product.coins .. " coins") or "") .. (product.bonus and (" (" .. product.bonus .. ")") or ""))
			or ""
		card(
			listFrame,
			order,
			product.name,
			sub,
			product.price .. " R$",
			Theme.Colors.Robux,
			product.oneTime and "ONE TIME" or "BUY",
			Theme.Colors.Gem,
			Theme.Colors.GemDark,
			function()
				Net.Client.fire("PromptProduct", key)
			end
		)
	end
end

local function fillPasses()
	local passes = ClientData.get("Passes") or {}
	local order = 0
	for _, key in { "DoubleLoot", "VIP", "ExtraTrapSlots", "BigVault", "RaidRadar" } do
		local pass = Products.Passes[key]
		order += 1
		local owned = passes[key] == true
		card(
			listFrame,
			order,
			pass.name,
			pass.description,
			owned and "OWNED" or (pass.price .. " R$"),
			owned and Theme.Colors.Success or Theme.Colors.Robux,
			owned and "OWNED" or "BUY",
			Theme.Colors.Primary,
			Theme.Colors.PrimaryDark,
			function()
				if not owned then
					Net.Client.fire("PromptPass", key)
				end
			end,
			owned
		)
	end
end

local function fillBoosts()
	local order = 0
	local shield = Products.DevProducts.Shield24h
	order += 1
	card(
		listFrame,
		order,
		shield.name,
		"Nobody can raid your base for a day. Raiding drops it.",
		shield.price .. " R$",
		Theme.Colors.Robux,
		"BUY",
		Theme.Colors.Accent,
		Theme.Colors.AccentDark,
		function()
			Net.Client.fire("PromptProduct", "Shield24h")
		end
	)
	-- Rewarded video placements (13+ and only when an ad is available).
	local adAvailable = false
	pcall(function()
		local result = AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		adAvailable = result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
	end)
	if adAvailable then
		order += 1
		card(
			listFrame,
			order,
			"2x Loot for 10 min",
			"Watch a short ad to double your raid loot for 10 minutes.",
			"FREE (ad)",
			Theme.Colors.Success,
			"WATCH AD",
			Theme.Colors.Success,
			Theme.Colors.SuccessDark,
			function()
				local result = Net.Client.invoke("ShowRewardedAd", "AdRaidKey")
				if result ~= "ShowCompleted" then
					HudController.toast("No ad available right now.", "warn")
				end
			end
		)
		order += 1
		card(
			listFrame,
			order,
			"1h Shield",
			"Watch a short ad for one hour of protection.",
			"FREE (ad)",
			Theme.Colors.Success,
			"WATCH AD",
			Theme.Colors.Success,
			Theme.Colors.SuccessDark,
			function()
				local result = Net.Client.invoke("ShowRewardedAd", "AdShield1h")
				if result ~= "ShowCompleted" then
					HudController.toast("No ad available right now.", "warn")
				end
			end
		)
	end
end

local function fillCosmetics(kind: string)
	local owned = cosmetics and cosmetics.Owned[kind] or {}
	local equippedKey = ({ Hammers = "Hammer", Sacks = "Sack", Trails = "Trail" })[kind]
	local equipped = cosmetics and cosmetics.Equipped[equippedKey]
	local order = 0
	for key, item in Cosmetics[kind] do
		order += 1
		local isOwned = owned[key] == true
		local isEquipped = equipped == key
		local price = item.pass and "VIP pass" or (item.price == 0 and "FREE" or (item.price .. " gems"))
		card(
			listFrame,
			item.price + order,
			item.name,
			isEquipped and "Equipped" or (isOwned and "Owned" or ""),
			price,
			item.pass and Theme.Colors.Primary or Theme.Colors.Gem,
			isEquipped and "EQUIPPED" or (isOwned and "EQUIP" or "BUY"),
			isOwned and Theme.Colors.Success or Theme.Colors.Gem,
			isOwned and Theme.Colors.SuccessDark or Theme.Colors.GemDark,
			function()
				if isOwned then
					Net.Client.fire("EquipCosmetic", kind, key)
				else
					Net.Client.fire("BuyCosmetic", kind, key)
				end
			end,
			isEquipped
		)
	end
end

local function fillThemes()
	local base = ClientData.get("Base")
	local owned = cosmetics and cosmetics.Owned.Themes or { Classic = true }
	local order = 0
	for _, name in Themes.Order do
		local palette = Themes.get(name)
		order += 1
		local isOwned = owned[name] == true
		local isCurrent = base and base.Theme == name
		card(
			listFrame,
			order,
			palette.name .. " Theme",
			"Recolours every piece of your base.",
			isOwned and "OWNED" or (palette.price == 0 and "FREE" or (palette.price .. " gems")),
			Theme.Colors.Gem,
			isCurrent and "CURRENT" or (isOwned and "APPLY" or "BUY"),
			Theme.Colors.Accent,
			Theme.Colors.AccentDark,
			function()
				Net.Client.fire("SetTheme", name)
			end,
			isCurrent
		)
	end
end

local function fill()
	clearList()
	if currentTab == "Gems" then
		fillGems()
	elseif currentTab == "Passes" then
		fillPasses()
	elseif currentTab == "Boosts" then
		fillBoosts()
	elseif currentTab == "Themes" then
		fillThemes()
	else
		fillCosmetics(currentTab)
	end
	for _, tab in tabsFrame:GetChildren() do
		if tab:IsA("TextButton") then
			tab.BackgroundColor3 = tab.Name == currentTab and Theme.Colors.Gem or Theme.Colors.PanelLight
		end
	end
end

local function build()
	frame, body = HudController.modal({ Name = "Shop", Size = UDim2.new(0, 760, 0, 480), Title = "SHOP" })
	tabsFrame = Make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = body,
		[1] = Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for order, name in TABS do
		local tab = Make("TextButton", {
			Name = name,
			Size = UDim2.new(0, 96, 1, 0),
			BackgroundColor3 = Theme.Colors.PanelLight,
			AutoButtonColor = false,
			Text = name,
			TextColor3 = Theme.Colors.Text,
			FontFace = Theme.Fonts.Display,
			TextSize = 15,
			LayoutOrder = order,
			Parent = tabsFrame,
			[1] = Components.corner(10),
		})
		tab.Activated:Connect(function()
			currentTab = name
			fill()
		end)
	end
	listFrame = Make("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.new(0, 0, 0, 44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = body,
		[1] = Make("UIGridLayout", {
			CellSize = UDim2.new(0, 200, 0, 150),
			CellPadding = UDim2.new(0, 10, 0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	return frame,
		{
			onOpen = function(tab)
				if type(tab) == "string" then
					currentTab = tab
				end
				fill()
			end,
		}
end

function ShopScreen.register()
	HudController.registerScreen("Shop", build)
	Net.Client.on("CosmeticsUpdated", function(data)
		cosmetics = data
		if HudController.isOpen("Shop") then
			fill()
		end
	end)
	Net.Client.on("PassesUpdated", function()
		if HudController.isOpen("Shop") then
			fill()
		end
	end)
	Net.Client.on("ProductGranted", function(key, channel)
		HudController.toast(
			channel == "Ad" and "Reward granted!" or "Purchase complete. Thank you!",
			"success",
			3
		)
		local _ = key
	end)
	local _ = Format
end

return ShopScreen
