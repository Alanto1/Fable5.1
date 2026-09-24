--!nonstrict
-- ProfileTemplate: the shape of a player's saved data. Add keys freely; never rename or
-- retype an existing key without a migration in DataService.Migrations.

local ProfileTemplate = {
	Version = 1,

	Coins = 0,
	Gems = 0,

	Stats = {
		Joins = 0,
		Playtime = 0, -- seconds
		FirstJoin = 0, -- os.time()
		LastSeen = 0,
		LoginStreak = 0,
		LastLoginDay = 0, -- os.time() // 86400
	},

	Settings = {
		Music = true,
		Sfx = true,
		Shake = true,
		NotificationsPrompted = false,
	},

	-- Monetization
	Passes = {}, -- { [passKey] = true } cache of owned gamepasses
	PurchaseHistory = {}, -- ring of recent receipt ids for idempotent ProcessReceipt
	Spend = { RobuxLifetime = 0, FirstPurchase = 0 },

	-- Live ops
	Codes = {}, -- { [code] = true }
	Quests = { Day = 0, Progress = {}, Claimed = {} },
	Tutorial = { Step = 0, Done = false },

	-- Game systems fill these in (see Shared/Data for the catalogs)
	Inventory = {},
	Cosmetics = { Owned = {}, Equipped = {} },
}

return ProfileTemplate
