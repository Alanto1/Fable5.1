--!nonstrict
-- CosmeticsService: buying and equipping hammer skins, sack skins and trails.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Data.Cosmetics)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local MonetizationService = require(script.Parent.MonetizationService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local CosmeticsService = {}

local KINDS = { "Hammers", "Sacks", "Trails" }
local EQUIP_KEY = { Hammers = "Hammer", Sacks = "Sack", Trails = "Trail" }

local function push(player: Player, profile)
	Net.Server.fire(player, "CosmeticsUpdated", profile.Data.Cosmetics)
	local character = player.Character
	if character then
		character:SetAttribute("HammerSkin", profile.Data.Cosmetics.Equipped.Hammer)
		character:SetAttribute("SackSkin", profile.Data.Cosmetics.Equipped.Sack)
		character:SetAttribute("TrailSkin", profile.Data.Cosmetics.Equipped.Trail)
	end
end

local function buy(player: Player, kind: string, key: string)
	local profile = DataService.getProfile(player)
	local item = Cosmetics.get(kind, key)
	if not profile or not item then
		return
	end
	local owned = profile.Data.Cosmetics.Owned[kind]
	if owned[key] then
		return
	end
	if item.pass then
		if not MonetizationService.ownsPass(player, item.pass) then
			MonetizationService.promptPass(player, item.pass)
			return
		end
	elseif item.price > 0 then
		if not PlayerService.addCurrency(player, "Gems", -item.price, "Shop", kind .. "_" .. key) then
			Net.Server.fire(player, "BuildError", "not enough gems")
			return
		end
	end
	owned[key] = true
	profile.Data.Cosmetics.Equipped[EQUIP_KEY[kind]] = key
	AnalyticsService.custom(player, "CosmeticBought", item.price, { kind = kind, key = key })
	push(player, profile)
end

local function equip(player: Player, kind: string, key: string)
	local profile = DataService.getProfile(player)
	if not profile or not Cosmetics.get(kind, key) then
		return
	end
	if not profile.Data.Cosmetics.Owned[kind][key] then
		return
	end
	profile.Data.Cosmetics.Equipped[EQUIP_KEY[kind]] = key
	push(player, profile)
end

function CosmeticsService.init()
	DataService.ProfileLoaded:Connect(function(player, profile)
		-- VIP owners get the golden hammer.
		if MonetizationService.ownsPass(player, "VIP") then
			profile.Data.Cosmetics.Owned.Hammers.Gold = true
		end
		push(player, profile)
		player.CharacterAdded:Connect(function()
			task.defer(push, player, profile)
		end)
	end)
	MonetizationService.PassGranted:Connect(function(player, passKey)
		if passKey == "VIP" then
			local profile = DataService.getProfile(player)
			if profile then
				profile.Data.Cosmetics.Owned.Hammers.Gold = true
				push(player, profile)
			end
		end
	end)
	Net.Server.on("BuyCosmetic", { Guard.enum(KINDS), Guard.string(24) }, buy, { rate = 3 })
	Net.Server.on("EquipCosmetic", { Guard.enum(KINDS), Guard.string(24) }, equip, { rate = 5 })
end

return CosmeticsService
