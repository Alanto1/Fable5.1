--!nonstrict
-- ProfileTemplate: the shape of a player's saved data. Add keys freely; never rename or
-- retype an existing key without a migration in DataService.Migrations.

local ProfileTemplate = {
	Version = 1,

	Coins = 250,
	Gems = 20,

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
	Spend = { RobuxLifetime = 0, FirstPurchase = 0, OneTime = {} },
	Boosts = { DoubleLootUntil = 0 },

	-- Live ops
	Codes = {}, -- { [code] = true }
	Quests = { Day = 0, Progress = {}, Claimed = {} },
	Tutorial = { Step = 0, Done = false },

	-- Base
	Base = {
		Level = 1,
		XP = 0,
		Theme = "Classic",
		Name = "",
		Layout = {}, -- filled with BaseLayout.starter() on first load
		Vault = { Stored = 0, LastTick = 0 },
		ShieldUntil = 0,
		LastRaidedAt = 0,
		Pending = {}, -- { { index = n, toLevel = n, readyAt = t } }
		RaidLog = {}, -- { { name, userId, amount, success, time, revenged } } newest last, max 10
		TotalLost = 0,
		TimesRaided = 0,
	},

	-- Raider
	Raider = {
		Hammer = 1,
		Sack = 1,
		Boots = 1,
		Trophies = 0,
		Raids = 0,
		Wins = 0,
		Stolen = 0,
		BestRaid = 0,
		BanditRaidTimes = {},
		LastLeagueWeek = 0,
	},

	Index = { Traps = {}, Walls = {}, Leagues = {}, Claimed = {} },

	Cosmetics = {
		Owned = {
			Hammers = { Classic = true },
			Sacks = { Classic = true },
			Trails = { None = true },
			Themes = { Classic = true },
		},
		Equipped = { Hammer = "Classic", Sack = "Classic", Trail = "None" },
	},
}

return ProfileTemplate
