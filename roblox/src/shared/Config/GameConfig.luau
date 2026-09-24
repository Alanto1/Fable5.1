--!nonstrict
-- GameConfig: platform-level constants. Game rules live in Shared/Data, not here.

local GameConfig = {
	GameName = "Raid a Base!",
	Version = "0.1.0",

	-- DataStore names. Bump the suffix to start fresh data (never do this after launch).
	DataStoreName = "PlayerProfiles_v1",
	InboxStoreName = "PlayerInbox_v1",
	OrderedStoreName = "Leaderboards_v1",

	-- Profile handling
	AutosaveInterval = 60, -- seconds
	SessionLockTTL = 180, -- seconds before a stale lock can be stolen
	LoadRetries = 6,
	LoadRetryDelay = 2.5,
	UseMockDataInStudio = true, -- keeps Studio play tests working without API access

	-- Currencies (names are used in analytics economy events)
	Currencies = {
		Coins = "Coins",
		Gems = "Gems",
	},

	-- Experience notification message ids (create the strings in Creator Hub, paste asset ids here)
	Notifications = {
		Raided = "", -- e.g. "You were raided by {raiderName}! They took {amount} coins. Get revenge."
		VaultFull = "", -- e.g. "Your vault is full. Collect your coins before someone else does."
	},

	-- Secrets store key names (Creator Hub > Secrets)
	Secrets = {
		OpenCloudApiKey = "OPEN_CLOUD_API_KEY",
	},

	-- Social links shown in game (must be Roblox-approved domains)
	Social = {
		GroupId = 0,
	},
}

return table.freeze(GameConfig)
