--!nonstrict
-- ScreensController: registers every modal screen with the HUD router.

local Screens = script.Parent.Parent:WaitForChild("Screens")

local ScreensController = {}

local LIST = { "ShopScreen", "BaseScreen", "LeagueScreen", "QuestsScreen", "SettingsScreen", "RaidLogScreen" }

function ScreensController.init()
	for _, name in LIST do
		local module = Screens:FindFirstChild(name)
		if module then
			local ok, screen = pcall(require, module)
			if ok and type(screen.register) == "function" then
				local regOk, err = pcall(screen.register)
				if not regOk then
					warn(("[Screens] %s.register failed: %s"):format(name, tostring(err)))
				end
			else
				warn(("[Screens] failed to load %s: %s"):format(name, tostring(screen)))
			end
		end
	end
end

return ScreensController
