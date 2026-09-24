--!nonstrict
-- NotificationService: experience notifications to opted-in players (13+) through Open Cloud.
-- Setup once in Creator Hub:
--   1. Create notification strings (Creator Hub > experience > Notifications) and paste their
--      asset ids into GameConfig.Notifications.
--   2. Create an Open Cloud API key with the `user.user-notification:write` scope and store it in
--      Secrets as OPEN_CLOUD_API_KEY.
--   3. Enable HTTP requests in Game Settings > Security.
-- Roblox delivers at most one notification per user per day per experience.

local HttpService = game:GetService("HttpService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)

local DataService = require(script.Parent.DataService)

local NotificationService = {}

local apiKey = nil
local lastSentDay: { [number]: number } = {} -- userId -> day index; belt-and-braces against the daily cap

local function getApiKey()
	if apiKey ~= nil then
		return apiKey or nil
	end
	local ok, secret = pcall(function()
		return HttpService:GetSecret(GameConfig.Secrets.OpenCloudApiKey)
	end)
	if ok and secret then
		apiKey = secret
	else
		apiKey = false
		warn("[Notifications] no Open Cloud API key in Secrets; notifications disabled")
	end
	return apiKey or nil
end

-- params: { name = "string or number", ... }; launchData: string? (max 200 bytes)
function NotificationService.send(userId: number, messageKey: string, params, launchData: string?): boolean
	local messageId = GameConfig.Notifications[messageKey]
	if not messageId or messageId == "" then
		return false
	end
	local key = getApiKey()
	if not key then
		return false
	end
	local today = os.time() // 86400
	if lastSentDay[userId] == today then
		return false
	end

	local parameters = {}
	for name, value in params or {} do
		if type(value) == "number" then
			parameters[name] = { int64_value = math.floor(value) }
		else
			parameters[name] = { string_value = tostring(value) }
		end
	end

	local body = {
		source = { universe = "universes/" .. game.GameId },
		payload = {
			type = "MOMENT",
			message_id = messageId,
			parameters = parameters,
			join_experience = launchData and { launch_data = launchData } or nil,
			analytics_data = { category = messageKey },
		},
	}

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = ("https://apis.roblox.com/cloud/v2/users/%d/notifications"):format(userId),
			Method = "POST",
			Headers = { ["x-api-key"] = key, ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(body),
		})
	end)
	if not ok then
		warn("[Notifications] request failed: " .. tostring(response))
		return false
	end
	if response.Success then
		lastSentDay[userId] = today
		return true
	end
	warn(("[Notifications] %d %s"):format(response.StatusCode, tostring(response.Body)))
	return false
end

function NotificationService.init()
	-- Client asks to show the opt-in prompt at a good moment (after the first successful raid).
	Net.Server.on("NotificationsPrompted", {}, function(player)
		local profile = DataService.getProfile(player)
		if profile then
			profile.Data.Settings.NotificationsPrompted = true
		end
	end, { rate = 1 })

	Net.Server.handle("CanPromptNotifications", {}, function(player)
		local profile = DataService.getProfile(player)
		if not profile or profile.Data.Settings.NotificationsPrompted then
			return false
		end
		local ok, can = pcall(function()
			return ExperienceNotificationService:CanPromptOptInAsync(player)
		end)
		return ok and can == true
	end, { rate = 1 })

	-- Guard.string is unused here but kept so the remote surface is explicit.
	local _ = Guard
end

return NotificationService
