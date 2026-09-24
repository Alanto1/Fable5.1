--!nonstrict
-- DataService: session-locked player profiles on top of DataStoreService.
--
-- Guarantees:
--   * One live session per profile. A second server that tries to load the same profile waits,
--     then steals only if the lock is older than SessionLockTTL (crashed server).
--   * Autosave every AutosaveInterval seconds, save on leave, save on server shutdown.
--   * Template reconciliation and versioned migrations on load.
--   * Falls back to an in-memory store in Studio when DataStore access is unavailable.
--
-- Usage:
--   local profile = DataService.getProfile(player)   -- nil until loaded, see DataService.ProfileLoaded
--   profile.Data.Coins += 10

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ProfileTemplate = require(Shared.Data.ProfileTemplate)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)

local DataService = {
	ProfileLoaded = Signal.new(), -- (player, profile)
	ProfileReleased = Signal.new(), -- (player, profile)
}

local profiles: { [Player]: any } = {}
local mockStore: { [string]: any } = {}
local useMock = false
local store = nil

-- Migrations run in order from the profile's stored Version up to the template Version.
-- Each entry receives the raw Data table and mutates it.
DataService.Migrations = {
	-- [2] = function(data) data.NewField = data.OldField; data.OldField = nil end,
}

------------------------------------------------------------------------------------------------
-- Store access with Studio fallback
------------------------------------------------------------------------------------------------

local function initStore()
	if store or useMock then
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
		-- Probe API access once; Studio without "Enable Studio Access to API Services" throws here.
		local probeOk = pcall(function()
			store:GetAsync("__probe__")
		end)
		if not probeOk and RunService:IsStudio() and GameConfig.UseMockDataInStudio then
			warn("[DataService] DataStore unavailable in Studio, using in-memory mock store")
			useMock = true
			store = nil
		end
	elseif RunService:IsStudio() and GameConfig.UseMockDataInStudio then
		warn("[DataService] DataStore unavailable in Studio, using in-memory mock store")
		useMock = true
	else
		error("[DataService] cannot access DataStore: " .. tostring(result))
	end
end

local function updateAsync(key: string, transform)
	if useMock then
		local newValue = transform(TableUtil.deepCopy(mockStore[key]))
		if newValue ~= nil then
			mockStore[key] = TableUtil.deepCopy(newValue)
		end
		return true, mockStore[key]
	end
	local ok, result = pcall(function()
		return store:UpdateAsync(key, transform)
	end)
	return ok, result
end

------------------------------------------------------------------------------------------------
-- Profile object
------------------------------------------------------------------------------------------------

local Profile = {}
Profile.__index = Profile

local function keyFor(userId: number): string
	return "p_" .. userId
end

local function newRecord()
	return {
		Data = TableUtil.deepCopy(ProfileTemplate),
		Meta = { Lock = nil, SaveCount = 0, Created = os.time() },
	}
end

local function lockIsOurs(record): boolean
	return record.Meta.Lock ~= nil and record.Meta.Lock.jobId == game.JobId
end

local function lockIsStale(record): boolean
	return record.Meta.Lock == nil or (os.time() - record.Meta.Lock.time) > GameConfig.SessionLockTTL
end

-- Writes Data back to the store while we hold the lock. Returns false if the lock was lost.
function Profile:Save(): boolean
	if not self.Active then
		return false
	end
	local data = self.Data
	local ok, result = updateAsync(self.Key, function(record)
		record = record or newRecord()
		if not lockIsOurs(record) and not lockIsStale(record) then
			return nil -- someone else owns it now; cancel the write
		end
		record.Data = data
		record.Meta.Lock = { jobId = game.JobId, time = os.time() }
		record.Meta.SaveCount += 1
		return record
	end)
	if not ok then
		warn(("[DataService] save failed for %s: %s"):format(self.Key, tostring(result)))
		return false
	end
	if result == nil and not useMock then
		warn(("[DataService] lost session lock for %s"):format(self.Key))
		self.Active = false
		return false
	end
	self.LastSave = os.clock()
	return true
end

-- Final write that also clears the lock.
function Profile:Release()
	if not self.Active then
		return
	end
	self.Active = false
	local data = self.Data
	local ok, result = updateAsync(self.Key, function(record)
		record = record or newRecord()
		if not lockIsOurs(record) and not lockIsStale(record) then
			return nil
		end
		record.Data = data
		record.Meta.Lock = nil
		record.Meta.SaveCount += 1
		return record
	end)
	if not ok then
		warn(("[DataService] release failed for %s: %s"):format(self.Key, tostring(result)))
	end
	DataService.ProfileReleased:Fire(self.Player, self)
end

------------------------------------------------------------------------------------------------
-- Load / lifecycle
------------------------------------------------------------------------------------------------

local function migrate(data)
	local version = data.Version or 1
	while version < ProfileTemplate.Version do
		version += 1
		local migration = DataService.Migrations[version]
		if migration then
			migration(data)
		end
		data.Version = version
	end
end

local function tryLoad(userId: number)
	local key = keyFor(userId)
	local loaded = nil
	for attempt = 1, GameConfig.LoadRetries do
		local ok, record = updateAsync(key, function(record)
			record = record or newRecord()
			if record.Meta.Lock and not lockIsOurs(record) and not lockIsStale(record) then
				return nil -- locked elsewhere; retry
			end
			record.Meta.Lock = { jobId = game.JobId, time = os.time() }
			return record
		end)
		if ok and record ~= nil then
			loaded = record
			break
		end
		if not ok then
			warn(("[DataService] load attempt %d failed for %s: %s"):format(attempt, key, tostring(record)))
		end
		task.wait(GameConfig.LoadRetryDelay)
	end
	return key, loaded
end

local function onPlayerAdded(player: Player)
	initStore()
	local key, record = tryLoad(player.UserId)
	if not record then
		player:Kick("Your data is still saving from another server. Please rejoin in a minute.")
		return
	end
	if not player.Parent then
		-- Player left while we were loading; drop the lock.
		updateAsync(key, function(rec)
			if rec and lockIsOurs(rec) then
				rec.Meta.Lock = nil
			end
			return rec
		end)
		return
	end

	local data = record.Data
	TableUtil.reconcile(data, ProfileTemplate)
	migrate(data)

	local profile = setmetatable({
		Player = player,
		UserId = player.UserId,
		Key = key,
		Data = data,
		Meta = record.Meta,
		Active = true,
		LastSave = os.clock(),
		LoadedAt = os.clock(),
	}, Profile)
	profiles[player] = profile

	data.Stats.Joins += 1
	if data.Stats.FirstJoin == 0 then
		data.Stats.FirstJoin = os.time()
	end
	local today = os.time() // 86400
	if data.Stats.LastLoginDay ~= today then
		data.Stats.LoginStreak = (data.Stats.LastLoginDay == today - 1) and (data.Stats.LoginStreak + 1) or 1
		data.Stats.LastLoginDay = today
	end

	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	profile.Data.Stats.LastSeen = os.time()
	profile.Data.Stats.Playtime += math.floor(os.clock() - profile.LoadedAt)
	profile:Release()
end

local function autosaveLoop()
	while true do
		task.wait(GameConfig.AutosaveInterval)
		for player, profile in profiles do
			if profile.Active and player.Parent then
				local ok = profile:Save()
				if not ok and not profile.Active then
					player:Kick("Your data was opened on another server. Please rejoin.")
				end
			end
			task.wait(0.2) -- spread writes to respect DataStore budgets
		end
	end
end

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------

function DataService.getProfile(player: Player)
	return profiles[player]
end

-- Yields until the profile exists or the player leaves. Returns nil if they left.
function DataService.waitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.getAllProfiles()
	return profiles
end

-- Read-only peek at an offline player's saved Data (nil if never played). Does not lock.
function DataService.peekOffline(userId: number)
	initStore()
	if useMock then
		local record = mockStore[keyFor(userId)]
		return record and TableUtil.deepCopy(record.Data) or nil
	end
	local ok, record = pcall(function()
		return store:GetAsync(keyFor(userId))
	end)
	if ok and record then
		return record.Data
	end
	return nil
end

function DataService.isMock(): boolean
	return useMock
end

function DataService.init()
	initStore()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(autosaveLoop)
	game:BindToClose(function()
		if RunService:IsStudio() and useMock then
			return
		end
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				profiles[player] = nil
				profile:Release()
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
