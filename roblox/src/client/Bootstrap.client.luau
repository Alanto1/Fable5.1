--!nonstrict
-- Client bootstrap: controllers init in order, then start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"InputController",
	"ClientData",
	"HudController",
}

local extra = Controllers:FindFirstChild("ControllersList") and require(Controllers.ControllersList) or {}
for _, name in extra do
	table.insert(ORDER, name)
end

local loaded = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	if not module then
		warn("[Client] missing controller " .. name)
		continue
	end
	local ok, controller = pcall(require, module)
	if not ok then
		warn(("[Client] failed to require %s: %s"):format(name, tostring(controller)))
		continue
	end
	if type(controller.init) == "function" then
		local initOk, err = pcall(controller.init)
		if not initOk then
			warn(("[Client] %s.init failed: %s"):format(name, tostring(err)))
		end
	end
	table.insert(loaded, { name = name, controller = controller })
end

for _, entry in loaded do
	if type(entry.controller.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.controller.start)
			if not ok then
				warn(("[Client] %s.start failed: %s"):format(entry.name, tostring(err)))
			end
		end)
	end
end

print(("[%s] client ready for %s"):format(GameConfig.GameName, Players.LocalPlayer.Name))
