--!nonstrict
-- PoolService: the raid target pool.
--   * Base snapshots live in a DataStore (read-mostly copies of a player's base for raiding).
--   * A MemoryStore sorted map indexes user ids by level bracket with a TTL so only recently
--     active bases are offered.
-- Falls back to in-memory tables in Studio without API access.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local RaidRules = require(Shared.RaidRules)

local DataService = require(script.Parent.DataService)

local SNAPSHOT_STORE = "BaseSnapshots_v1"
local POOL_MAP = "RaidPool_v1"

local PoolService = {}

local snapshotStore = nil
local poolMap = nil
local useMock = false
local mockSnapshots: { [number]: any } = {}
local mockPool: { [string]: any } = {}

local function init()
	if snapshotStore or useMock then
		return
	end
	if DataService.isMock() then
		useMock = true
		return
	end
	local ok = pcall(function()
		snapshotStore = DataStoreService:GetDataStore(SNAPSHOT_STORE)
		poolMap = MemoryStoreService:GetSortedMap(POOL_MAP)
	end)
	if not ok then
		warn("[Pool] stores unavailable, using in-memory pool")
		useMock = true
	end
end

local function poolKey(bracket: number, userId: number): string
	return ("%02d:%d"):format(bracket, userId)
end

-- Publish a player's base for others to raid.
function PoolService.publish(userId: number, snapshot)
	init()
	snapshot.updatedAt = os.time()
	local bracket = RaidRules.bracket(snapshot.level)
	if useMock then
		mockSnapshots[userId] = snapshot
		mockPool[poolKey(bracket, userId)] =
			{ userId = userId, level = snapshot.level, rating = snapshot.rating }
		return true
	end
	local ok, err = pcall(function()
		snapshotStore:SetAsync("b_" .. userId, snapshot)
	end)
	if not ok then
		warn("[Pool] snapshot save failed: " .. tostring(err))
		return false
	end
	pcall(function()
		poolMap:SetAsync(
			poolKey(bracket, userId),
			{ userId = userId, level = snapshot.level, rating = snapshot.rating },
			Balance.Matchmaking.PoolTTL
		)
	end)
	return true
end

-- Candidates in a bracket, excluding one user. Returns { { userId, level, rating } }.
function PoolService.candidates(bracket: number, excludeUserId: number)
	init()
	local out = {}
	if useMock then
		local prefix = ("%02d:"):format(bracket)
		for key, entry in mockPool do
			if key:sub(1, #prefix) == prefix and entry.userId ~= excludeUserId then
				table.insert(out, entry)
			end
		end
		return out
	end
	local ok, items = pcall(function()
		local lower = ("%02d:"):format(bracket)
		local upper = ("%02d:~"):format(bracket)
		return poolMap:GetRangeAsync(
			Enum.SortDirection.Ascending,
			Balance.Matchmaking.MaxCandidates,
			lower,
			upper
		)
	end)
	if ok and items then
		for _, item in items do
			local entry = item.value
			if type(entry) == "table" and entry.userId ~= excludeUserId then
				table.insert(out, entry)
			end
		end
	end
	return out
end

function PoolService.loadSnapshot(userId: number)
	init()
	if useMock then
		return mockSnapshots[userId]
	end
	local ok, snapshot = pcall(function()
		return snapshotStore:GetAsync("b_" .. userId)
	end)
	if ok then
		return snapshot
	end
	return nil
end

-- Record a raid against a snapshot so the same coins are not offered twice before the owner
-- reconciles through their inbox.
function PoolService.markRaided(userId: number, stolen: number)
	init()
	local function transform(snapshot)
		if not snapshot then
			return nil
		end
		snapshot.stored = math.max(0, (snapshot.stored or 0) - stolen)
		snapshot.lastRaidedAt = os.time()
		return snapshot
	end
	if useMock then
		mockSnapshots[userId] = transform(mockSnapshots[userId])
		return
	end
	pcall(function()
		snapshotStore:UpdateAsync("b_" .. userId, transform)
	end)
end

function PoolService.init()
	init()
end

return PoolService
