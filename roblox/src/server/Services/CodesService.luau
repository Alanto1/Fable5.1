--!nonstrict
-- CodesService: promo code redemption.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Codes = require(Shared.Data.Codes)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local BaseService = require(script.Parent.BaseService)

local CodesService = {}

local function redeem(player: Player, raw: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local code = raw:upper():gsub("[^%w]", "")
	local reward = Codes[code]
	if not reward then
		Net.Server.fire(player, "CodeResult", false, "That code does not exist.")
		return
	end
	if reward.expires ~= 0 and os.time() > reward.expires then
		Net.Server.fire(player, "CodeResult", false, "That code has expired.")
		return
	end
	if profile.Data.Codes[code] then
		Net.Server.fire(player, "CodeResult", false, "You already used that code.")
		return
	end
	profile.Data.Codes[code] = true
	local parts = {}
	if reward.coins then
		PlayerService.addCurrency(player, "Coins", reward.coins, "TimedReward", "Code_" .. code)
		table.insert(parts, reward.coins .. " coins")
	end
	if reward.gems then
		PlayerService.addCurrency(player, "Gems", reward.gems, "TimedReward", "Code_" .. code)
		table.insert(parts, reward.gems .. " gems")
	end
	if reward.shieldSeconds then
		BaseService.giveShield(player, reward.shieldSeconds, "Code")
		table.insert(parts, "a shield")
	end
	AnalyticsService.custom(player, "CodeRedeemed", 1, { code = code })
	Net.Server.fire(player, "CodeResult", true, "Redeemed: " .. table.concat(parts, ", "))
end

function CodesService.init()
	Net.Server.on("RedeemCode", { Guard.string(24) }, redeem, { rate = 1, burst = 3 })
end

return CodesService
