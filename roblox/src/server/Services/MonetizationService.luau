--!nonstrict
-- MonetizationService: gamepasses, developer products and rewarded video, with idempotent
-- receipt processing and analytics. Product definitions live in Shared/Data/Products.

local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Products = require(Shared.Data.Products)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)
local Signal = require(Shared.Util.Signal)

local DataService = require(script.Parent.DataService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local RECEIPT_HISTORY = 50

local MonetizationService = {
	PassGranted = Signal.new(), -- (player, passKey)
	ProductGranted = Signal.new(), -- (player, productKey, product, channel)
}

local passById: { [number]: string } = {}
local productById: { [number]: string } = {}

-- Optional custom grant handlers registered by game systems: key -> function(player, profile, product)
local grantHandlers: { [string]: (Player, any, any) -> boolean } = {}

function MonetizationService.registerGrant(productKey: string, handler)
	grantHandlers[productKey] = handler
end

------------------------------------------------------------------------------------------------
-- Gamepasses
------------------------------------------------------------------------------------------------

function MonetizationService.ownsPass(player: Player, passKey: string): boolean
	local profile = DataService.getProfile(player)
	if profile and profile.Data.Passes[passKey] then
		return true
	end
	return false
end

local function refreshPasses(player: Player, profile)
	for passKey, pass in Products.Passes do
		if pass.id ~= 0 and not profile.Data.Passes[passKey] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				profile.Data.Passes[passKey] = true
				MonetizationService.PassGranted:Fire(player, passKey)
			end
		end
	end
	Net.Server.fire(player, "PassesUpdated", profile.Data.Passes)
end

function MonetizationService.promptPass(player: Player, passKey: string)
	local pass = Products.Passes[passKey]
	if not pass or pass.id == 0 then
		warn("[Monetization] pass not configured: " .. tostring(passKey))
		return
	end
	if MonetizationService.ownsPass(player, passKey) then
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)
end

------------------------------------------------------------------------------------------------
-- Developer products
------------------------------------------------------------------------------------------------

local function defaultGrant(player: Player, profile, product): boolean
	local data = profile.Data
	if product.oneTime then
		data.Spend.OneTime = data.Spend.OneTime or {}
		if data.Spend.OneTime[product.key] then
			return false
		end
		data.Spend.OneTime[product.key] = true
	end
	if product.gems then
		data.Gems += product.gems
		AnalyticsService.economy(
			player,
			"Source",
			GameConfig.Currencies.Gems,
			product.gems,
			data.Gems,
			"IAP",
			product.key
		)
	end
	if product.coins then
		data.Coins += product.coins
		AnalyticsService.economy(
			player,
			"Source",
			GameConfig.Currencies.Coins,
			product.coins,
			data.Coins,
			"IAP",
			product.key
		)
	end
	return true
end

local function grantProduct(player: Player, profile, productKey: string, channel: string): boolean
	local product = Products.DevProducts[productKey]
	product.key = productKey
	local handler = grantHandlers[productKey]
	local ok, granted = pcall(function()
		local base = defaultGrant(player, profile, product)
		if handler then
			return handler(player, profile, product) ~= false and base
		end
		return base
	end)
	if not ok then
		warn(("[Monetization] grant %s failed: %s"):format(productKey, tostring(granted)))
		return false
	end
	if granted then
		MonetizationService.ProductGranted:Fire(player, productKey, product, channel)
		Net.Server.fire(player, "ProductGranted", productKey, channel)
	end
	return granted
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.waitForProfile(player, 20)
	if not profile or not profile.Active then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local history = profile.Data.PurchaseHistory
	if table.find(history, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey = productById[receipt.ProductId]
	if not productKey then
		warn("[Monetization] receipt for unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local channel = tostring(receipt.ProductPurchaseChannel)
	local isAd = receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward
	local granted = grantProduct(player, profile, productKey, isAd and "Ad" or "Robux")
	if not granted then
		-- One-time product bought twice, or a handler refused. Robux were charged; log and grant
		-- anyway so the player is not charged repeatedly by retries.
		warn(("[Monetization] product %s not granted for %s (%s)"):format(productKey, player.Name, channel))
	end

	table.insert(history, receipt.PurchaseId)
	while #history > RECEIPT_HISTORY do
		table.remove(history, 1)
	end
	if not isAd then
		profile.Data.Spend.RobuxLifetime += receipt.CurrencySpent or 0
		if profile.Data.Spend.FirstPurchase == 0 then
			profile.Data.Spend.FirstPurchase = os.time()
		end
	end

	-- Persist immediately so a crash cannot double-grant.
	local saved = profile:Save()
	if not saved then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.promptProduct(player: Player, productKey: string)
	local product = Products.DevProducts[productKey]
	if not product or product.id == 0 then
		warn("[Monetization] product not configured: " .. tostring(productKey))
		return
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)
end

------------------------------------------------------------------------------------------------
-- Rewarded video
------------------------------------------------------------------------------------------------

function MonetizationService.showRewardedAd(player: Player, productKey: string)
	local product = Products.DevProducts[productKey]
	if not product or not product.adReward or product.id == 0 then
		return "NotConfigured"
	end
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(product.id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	if not ok then
		warn("[Monetization] rewarded ad failed: " .. tostring(result))
		return "Error"
	end
	return tostring(result)
end

------------------------------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------------------------------

function MonetizationService.init()
	for key, pass in Products.Passes do
		if pass.id ~= 0 then
			passById[pass.id] = key
		end
	end
	for key, product in Products.DevProducts do
		if product.id ~= 0 then
			productById[product.id] = key
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local passKey = passById[passId]
		local profile = DataService.getProfile(player)
		if passKey and profile then
			profile.Data.Passes[passKey] = true
			MonetizationService.PassGranted:Fire(player, passKey)
			Net.Server.fire(player, "PassesUpdated", profile.Data.Passes)
			AnalyticsService.custom(
				player,
				"PassPurchased",
				Products.Passes[passKey].price,
				{ pass = passKey }
			)
			profile:Save()
		end
	end)

	DataService.ProfileLoaded:Connect(function(player, profile)
		task.spawn(refreshPasses, player, profile)
	end)

	Net.Server.on("PromptPass", { Guard.keyOf(Products.Passes) }, function(player, passKey)
		MonetizationService.promptPass(player, passKey)
	end, { rate = 2 })

	Net.Server.on("PromptProduct", { Guard.keyOf(Products.DevProducts) }, function(player, productKey)
		MonetizationService.promptProduct(player, productKey)
	end, { rate = 2 })

	Net.Server.handle("ShowRewardedAd", { Guard.keyOf(Products.DevProducts) }, function(player, productKey)
		return MonetizationService.showRewardedAd(player, productKey)
	end, { rate = 1, burst = 2 })
end

return MonetizationService
