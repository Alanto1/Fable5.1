--!nonstrict
-- ClientData: the client's mirror of the parts of the profile it is allowed to see.
-- Systems read ClientData.get("Coins") and subscribe to ClientData.Changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net.Net)
local Signal = require(Shared.Util.Signal)

local ClientData = {
	Loaded = Signal.new(), -- ()
	Changed = Signal.new(), -- (key, value, delta?)
	IsLoaded = false,
}

local state = {}

function ClientData.get(key: string)
	return state[key]
end

function ClientData.set(key: string, value, delta)
	state[key] = value
	ClientData.Changed:Fire(key, value, delta)
end

function ClientData.snapshot()
	return state
end

local function apply(snapshot)
	for key, value in snapshot do
		state[key] = value
	end
	ClientData.IsLoaded = true
	ClientData.Loaded:Fire()
	for key, value in snapshot do
		ClientData.Changed:Fire(key, value)
	end
end

function ClientData.init()
	Net.Client.on("ProfileSnapshot", apply)
	Net.Client.on("CurrencyChanged", function(currency, amount, delta)
		ClientData.set(currency, amount, delta)
	end)
	Net.Client.on("PassesUpdated", function(passes)
		ClientData.set("Passes", passes)
	end)
	-- If the server pushed the snapshot before our listeners existed, ask for it again.
	task.delay(2, function()
		if not ClientData.IsLoaded then
			local snapshot = Net.Client.invoke("RequestSnapshot")
			if snapshot and not ClientData.IsLoaded then
				apply(snapshot)
			end
		end
	end)
end

return ClientData
