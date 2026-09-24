--!nonstrict
-- PlayerService: per-player lifecycle glue. Sets up leaderstats, pushes the initial data
-- snapshot to the client, and mirrors currency changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net.Net)
local Signal = require(Shared.Util.Signal)

local DataService = require(script.Parent.DataService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local PlayerService = {
	CurrencyChanged = Signal.new(), -- (player, currency, newAmount, delta)
}

local function setupLeaderstats(player: Player, profile)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Data.Coins
	coins.Parent = leaderstats

	leaderstats.Parent = player
	return leaderstats
end

-- Snapshot sent to the client on load. Keep it small; systems push their own deltas afterwards.
local function snapshot(profile)
	local data = profile.Data
	return {
		Coins = data.Coins,
		Gems = data.Gems,
		Settings = data.Settings,
		Passes = data.Passes,
		Tutorial = data.Tutorial,
		Stats = { LoginStreak = data.Stats.LoginStreak, Joins = data.Stats.Joins },
	}
end

function PlayerService.addCurrency(
	player: Player,
	currency: string,
	amount: number,
	reason: string,
	sku: string?
)
	local profile = DataService.getProfile(player)
	if not profile or amount == 0 then
		return false
	end
	local data = profile.Data
	local balance = data[currency]
	if balance == nil then
		error("unknown currency " .. tostring(currency))
	end
	if amount < 0 and balance + amount < 0 then
		return false
	end
	data[currency] = balance + amount
	if currency == "Coins" then
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild("Coins")
		if value then
			value.Value = data.Coins
		end
	end
	AnalyticsService.economy(
		player,
		amount > 0 and "Source" or "Sink",
		currency,
		math.abs(amount),
		data[currency],
		reason,
		sku
	)
	Net.Server.fire(player, "CurrencyChanged", currency, data[currency], amount)
	PlayerService.CurrencyChanged:Fire(player, currency, data[currency], amount)
	return true
end

function PlayerService.canAfford(player: Player, currency: string, amount: number): boolean
	local profile = DataService.getProfile(player)
	return profile ~= nil and (profile.Data[currency] or 0) >= amount
end

function PlayerService.init()
	DataService.ProfileLoaded:Connect(function(player, profile)
		setupLeaderstats(player, profile)
		Net.Server.fire(player, "ProfileSnapshot", snapshot(profile))
		AnalyticsService.onboarding(player, "Spawned")
		AnalyticsService.custom(player, "SessionStart", profile.Data.Stats.Joins, {
			streak = tostring(profile.Data.Stats.LoginStreak),
			version = GameConfig.Version,
		})
	end)

	Net.Server.on("SetSetting", {
		function(v)
			return type(v) == "string" and #v <= 32
		end,
		function(v)
			return type(v) == "boolean"
		end,
	}, function(player, key, value)
		local profile = DataService.getProfile(player)
		if profile and profile.Data.Settings[key] ~= nil and key ~= "NotificationsPrompted" then
			profile.Data.Settings[key] = value
		end
	end, { rate = 5 })

	-- Client re-requests a snapshot if it loaded after the initial push (e.g. slow client boot).
	Net.Server.handle("RequestSnapshot", {}, function(player)
		local profile = DataService.getProfile(player)
		return profile and snapshot(profile) or nil
	end, { rate = 1, burst = 3 })

	Players.PlayerRemoving:Connect(function(player)
		AnalyticsService.custom(player, "SessionEnd")
	end)
end

return PlayerService
