--!nonstrict
-- Server bootstrap. Services are initialised in dependency order; each exposes init() and may
-- expose start() for work that needs every service to exist first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local Net = require(Shared.Net.Net)
local RemoteNames = require(Shared.Net.RemoteNames)

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")

Net.Server.declare(RemoteNames)

local ORDER = {
	"AnalyticsService",
	"DataService",
	"InboxService",
	"PlayerService",
	"MonetizationService",
	"NotificationService",
	-- game systems are appended below by the game module list
}

local GAME_SYSTEMS = Services:FindFirstChild("SystemsList") and require(Services.SystemsList) or {}
for _, name in GAME_SYSTEMS do
	table.insert(ORDER, name)
end

local loaded = {}
local started = os.clock()

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if not module then
		warn("[Bootstrap] missing service " .. name)
		continue
	end
	local ok, service = pcall(require, module)
	if not ok then
		error(("[Bootstrap] failed to require %s: %s"):format(name, tostring(service)))
	end
	if type(service.init) == "function" then
		local initOk, err = pcall(service.init)
		if not initOk then
			error(("[Bootstrap] %s.init failed: %s"):format(name, tostring(err)))
		end
	end
	table.insert(loaded, { name = name, service = service })
end

for _, entry in loaded do
	if type(entry.service.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.service.start)
			if not ok then
				warn(("[Bootstrap] %s.start failed: %s"):format(entry.name, tostring(err)))
			end
		end)
	end
end

print(
	("[%s v%s] server ready: %d services in %.0f ms"):format(
		GameConfig.GameName,
		GameConfig.Version,
		#loaded,
		(os.clock() - started) * 1000
	)
)
