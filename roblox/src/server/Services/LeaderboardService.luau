--!nonstrict
-- LeaderboardService: global top-50 boards for trophies and total stolen, plus weekly league
-- rewards. OrderedDataStore writes are batched to stay inside budgets.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local RaidRules = require(Shared.RaidRules)
local Net = require(Shared.Net.Net)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)

local LeaderboardService = {}

local BOARDS = { Trophies = "LB_Trophies_v1", Stolen = "LB_Stolen_v1" }
local TOP = 50
local REFRESH = 180
local WRITE_INTERVAL = 120

local stores = {}
local cache = { Trophies = {}, Stolen = {} }
local names: { [number]: string } = {}
local useMock = false

local function init()
	if useMock or DataService.isMock() then
		useMock = true
		return
	end
	for key, name in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if ok then
			stores[key] = store
		else
			useMock = true
		end
	end
end

local function nameFor(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and name or "Player"
	return names[userId]
end

local function writeAll()
	for player, profile in DataService.getAllProfiles() do
		local raider = profile.Data.Raider
		names[player.UserId] = player.DisplayName
		if useMock then
			continue
		end
		pcall(function()
			stores.Trophies:SetAsync(tostring(player.UserId), math.floor(raider.Trophies))
		end)
		pcall(function()
			stores.Stolen:SetAsync(tostring(player.UserId), math.floor(raider.Stolen))
		end)
		task.wait(0.5)
	end
end

local function refresh()
	if useMock then
		-- Build boards from online players only.
		for key in BOARDS do
			local list = {}
			for player, profile in DataService.getAllProfiles() do
				table.insert(list, {
					userId = player.UserId,
					name = player.DisplayName,
					value = math.floor(profile.Data.Raider[key]),
				})
			end
			table.sort(list, function(a, b)
				return a.value > b.value
			end)
			cache[key] = list
		end
		return
	end
	for key, store in stores do
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, TOP)
		end)
		if ok then
			local list = {}
			for rank, entry in pages:GetCurrentPage() do
				local userId = tonumber(entry.key)
				table.insert(
					list,
					{ rank = rank, userId = userId, name = nameFor(userId), value = entry.value }
				)
			end
			cache[key] = list
		end
	end
end

local function weekIndex(): number
	return os.time() // (7 * 86400)
end

local function grantWeekly(player: Player, profile)
	local raider = profile.Data.Raider
	local week = weekIndex()
	if raider.LastLeagueWeek == 0 then
		raider.LastLeagueWeek = week
		return
	end
	if raider.LastLeagueWeek ~= week then
		local league = RaidRules.leagueFor(raider.Trophies)
		raider.LastLeagueWeek = week
		profile.Data.Index.Leagues[league.name] = true
		PlayerService.addCurrency(player, "Gems", league.weeklyGems, "TimedReward", "League_" .. league.name)
		Net.Server.fire(player, "LeagueReward", league.name, league.weeklyGems)
	end
end

function LeaderboardService.init()
	init()
	DataService.ProfileLoaded:Connect(function(player, profile)
		grantWeekly(player, profile)
		local league = RaidRules.leagueFor(profile.Data.Raider.Trophies)
		profile.Data.Index.Leagues[league.name] = true
	end)
	Net.Server.handle("GetLeaderboards", {}, function(player)
		local profile = DataService.getProfile(player)
		local raider = profile and profile.Data.Raider
		return {
			Trophies = cache.Trophies,
			Stolen = cache.Stolen,
			Me = raider and {
				Trophies = raider.Trophies,
				Stolen = raider.Stolen,
				Raids = raider.Raids,
				Wins = raider.Wins,
				Best = raider.BestRaid,
			} or nil,
			Leagues = Balance.Leagues,
		}
	end, { rate = 1, burst = 3 })
	task.spawn(function()
		task.wait(5)
		refresh()
		while true do
			task.wait(REFRESH)
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(WRITE_INTERVAL)
			writeAll()
		end
	end)
	game:BindToClose(function()
		if not useMock then
			writeAll()
		end
	end)
end

return LeaderboardService
