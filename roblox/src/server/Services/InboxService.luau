--!nonstrict
-- InboxService: append-only messages for players who may be offline or on another server.
-- Used for anything that happens to a player's saved state while they are not the owner of the
-- session lock (raid results, gifts, admin grants). The owning server drains and applies the
-- inbox on load and every drain interval.
--
--   InboxService.push(userId, { type = "RaidResult", ... })
--   InboxService.registerHandler("RaidResult", function(player, profile, entry) ... end)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Util.TableUtil)

local DataService = require(script.Parent.DataService)

local MAX_ENTRIES = 60
local DRAIN_INTERVAL = 45

local InboxService = {}

local handlers: { [string]: (Player, any, any) -> () } = {}
local store = nil
local mock: { [string]: any } = {}
local useMock = false

local function initStore()
	if store or useMock then
		return
	end
	if DataService.isMock() then
		useMock = true
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.InboxStoreName)
	end)
	if ok then
		store = result
	elseif RunService:IsStudio() then
		useMock = true
	else
		error("[InboxService] cannot access DataStore: " .. tostring(result))
	end
end

local function keyFor(userId: number): string
	return "i_" .. userId
end

local function update(key: string, transform)
	initStore()
	if useMock then
		local newValue = transform(TableUtil.deepCopy(mock[key]))
		if newValue ~= nil then
			mock[key] = newValue
		end
		return true, mock[key]
	end
	return pcall(function()
		return store:UpdateAsync(key, transform)
	end)
end

function InboxService.registerHandler(entryType: string, handler)
	handlers[entryType] = handler
end

function InboxService.push(userId: number, entry): boolean
	entry.time = entry.time or os.time()
	local ok, err = update(keyFor(userId), function(list)
		list = list or {}
		table.insert(list, entry)
		while #list > MAX_ENTRIES do
			table.remove(list, 1)
		end
		return list
	end)
	if not ok then
		warn(("[InboxService] push failed for %d: %s"):format(userId, tostring(err)))
	end
	return ok
end

-- Atomically takes every pending entry for the user.
function InboxService.drain(userId: number)
	local taken = {}
	local ok, err = update(keyFor(userId), function(list)
		if not list or #list == 0 then
			return nil -- nothing to do; cancel write
		end
		taken = list
		return {}
	end)
	if not ok then
		warn(("[InboxService] drain failed for %d: %s"):format(userId, tostring(err)))
		return {}
	end
	return taken
end

local function applyFor(player: Player)
	local profile = DataService.getProfile(player)
	if not profile or not profile.Active then
		return
	end
	local entries = InboxService.drain(player.UserId)
	for _, entry in entries do
		local handler = handlers[entry.type]
		if handler then
			local ok, err = pcall(handler, player, profile, entry)
			if not ok then
				warn(("[InboxService] handler %s failed: %s"):format(entry.type, tostring(err)))
			end
		else
			warn(("[InboxService] no handler for %s"):format(tostring(entry.type)))
		end
	end
end

function InboxService.init()
	initStore()
	DataService.ProfileLoaded:Connect(function(player)
		applyFor(player)
	end)
	task.spawn(function()
		while true do
			task.wait(DRAIN_INTERVAL)
			for _, player in Players:GetPlayers() do
				applyFor(player)
				task.wait(0.3)
			end
		end
	end)
end

return InboxService
