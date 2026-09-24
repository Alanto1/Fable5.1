--!nonstrict
-- Net: the only way the client and server talk.
-- Server side: Net.Server.on(name, guards, handler, options) / fire / fireAll / handle (RemoteFunction).
-- Client side: Net.Client.on(name, handler) / fire / invoke.
-- Every server handler is guarded (see Guard.luau) and rate limited per player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Guard = require(script.Parent.Guard)

local REMOTES_FOLDER_NAME = "Remotes"
local DEFAULT_RATE = 20 -- calls per second per player
local DEFAULT_BURST = 40
local WAIT_TIMEOUT = 15

local Net = { Server = {}, Client = {} }

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = REMOTES_FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, WAIT_TIMEOUT)
		end
	end
	return folder
end

------------------------------------------------------------------------------------------------
-- Server
------------------------------------------------------------------------------------------------

local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local violations: { [Player]: number } = {}

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		violations[player] = nil
	end)
end

local function allow(player: Player, name: string, rate: number, burst: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[name]
	local now = os.clock()
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	violations[player] = (violations[player] or 0) + 1
	if violations[player] % 50 == 0 then
		warn(
			("[Net] %s exceeded rate limit on %s (%d violations)"):format(
				player.Name,
				name,
				violations[player]
			)
		)
	end
	return false
end

local function getRemote(name: string, className: string): Instance
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		if not remote:IsA(className) then
			error(("[Net] remote %s exists as %s, expected %s"):format(name, remote.ClassName, className))
		end
		return remote
	end
	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- options: { rate = number?, burst = number? }
function Net.Server.on(name: string, guards, handler, options)
	assert(RunService:IsServer(), "Net.Server used on client")
	options = options or {}
	local rate = options.rate or DEFAULT_RATE
	local burst = options.burst or math.max(DEFAULT_BURST, rate * 2)
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote.OnServerEvent:Connect(function(player, ...)
		if not allow(player, name, rate, burst) then
			return
		end
		local ok, reason = Guard.check(guards, ...)
		if not ok then
			violations[player] = (violations[player] or 0) + 1
			if RunService:IsStudio() then
				warn(("[Net] %s sent bad args to %s: %s"):format(player.Name, name, reason))
			end
			return
		end
		handler(player, ...)
	end)
	return remote
end

-- RemoteFunction handled on the server. The handler's return values are sent back to the client.
-- Never invoke the client from the server; it can hang the server thread forever.
function Net.Server.handle(name: string, guards, handler, options)
	assert(RunService:IsServer(), "Net.Server used on client")
	options = options or {}
	local rate = options.rate or DEFAULT_RATE
	local burst = options.burst or math.max(DEFAULT_BURST, rate * 2)
	local remote = getRemote(name, "RemoteFunction") :: RemoteFunction
	remote.OnServerInvoke = function(player, ...)
		if not allow(player, name, rate, burst) then
			return nil
		end
		local ok = Guard.check(guards, ...)
		if not ok then
			return nil
		end
		return handler(player, ...)
	end
	return remote
end

function Net.Server.event(name: string): RemoteEvent
	return getRemote(name, "RemoteEvent") :: RemoteEvent
end

function Net.Server.fire(player: Player, name: string, ...)
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote:FireClient(player, ...)
end

function Net.Server.fireAll(name: string, ...)
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	remote:FireAllClients(...)
end

function Net.Server.fireExcept(exclude: Player, name: string, ...)
	local remote = getRemote(name, "RemoteEvent") :: RemoteEvent
	for _, player in Players:GetPlayers() do
		if player ~= exclude then
			remote:FireClient(player, ...)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Client
------------------------------------------------------------------------------------------------

local function waitRemote(name: string, className: string): Instance?
	local folder = getFolder()
	if not folder then
		return nil
	end
	local remote = folder:WaitForChild(name, WAIT_TIMEOUT)
	if not remote then
		warn(("[Net] remote %s never appeared"):format(name))
		return nil
	end
	assert(
		remote:IsA(className),
		("[Net] remote %s is %s, expected %s"):format(name, remote.ClassName, className)
	)
	return remote
end

function Net.Client.on(name: string, handler)
	assert(RunService:IsClient(), "Net.Client used on server")
	local remote = waitRemote(name, "RemoteEvent") :: RemoteEvent?
	if not remote then
		return nil
	end
	return remote.OnClientEvent:Connect(handler)
end

function Net.Client.fire(name: string, ...)
	assert(RunService:IsClient(), "Net.Client used on server")
	local remote = waitRemote(name, "RemoteEvent") :: RemoteEvent?
	if remote then
		remote:FireServer(...)
	end
end

function Net.Client.invoke(name: string, ...)
	assert(RunService:IsClient(), "Net.Client used on server")
	local remote = waitRemote(name, "RemoteFunction") :: RemoteFunction?
	if not remote then
		return nil
	end
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		warn(("[Net] invoke %s failed: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

return Net
