--!nonstrict
-- Balance: every tunable number in the game. See docs/roblox/05-economy.md for the intent.
-- Change numbers here, never in systems.

local Balance = {
	Grid = {
		Size = 16, -- cells per side
		Cell = 4, -- studs per cell
		-- Entrance strip on the south edge (max z) that must stay clear: cells x0..x1, z0..z1
		Entrance = { x0 = 6, x1 = 9, z0 = 14, z1 = 15 },
	},

	Vault = {
		BaseCapacity = 2000,
		CapacityGrowth = 1.8,
		StealFraction = 0.25,
	},

	Mine = {
		BaseIncome = 120, -- coins per hour at level 1
		IncomeGrowth = 1.45,
		SmashFraction = 0.10, -- share of hourly income dropped when a raider smashes it
		MaxOfflineHours = 12, -- accrual cap while away
	},

	Raid = {
		Duration = 90,
		ExtraSecondsPerVaultLevel = 15,
		VaultLevelForExtra = 3,
		Countdown = 3,
		KeepOnFail = 0.30,
		ClutchSeconds = 3,
		MaxRaiders = 4,
		SwingCooldown = 0.45,
		SwingRange = 9,
		PickupRange = 7,
		ReRollCost = 50,
		FreeReRolls = 1,
		RadarReRolls = 2,
		LiveTargetChance = 0.5,
		ResultsSeconds = 6,
		PileValue = 25, -- coins per pile; piles are merged into bigger denominations
		MaxPiles = 60,
		GuardsPerExtraRaider = 1,
	},

	Player = {
		MaxHealth = 100,
		WalkSpeed = 16,
		SprintSpeed = 22,
		DashSpeed = 60,
		DashSeconds = 0.25,
		DashCooldown = 4,
		SprintStaminaSeconds = 6,
		StaminaRegenSeconds = 5,
	},

	Gear = {
		Hammer = { BaseDamage = 50, Growth = 1.5, MaxLevel = 15 },
		Sack = { BaseCapacity = 500, Growth = 1.6, MaxLevel = 15, SlowAtFull = 0.4 },
		Boots = { BaseRelief = 0.0, ReliefPerLevel = 0.06, MaxLevel = 8 }, -- reduces sack slow
		BaseCost = 400,
		CostGrowth = 1.7,
	},

	XP = {
		Base = 100,
		Exponent = 1.6,
		MaxLevel = 30,
		PerCoinSpent = 0.1,
		PerRaidWin = 25,
		PerRaidLoss = 5,
	},

	Upgrade = {
		InstantThroughLevel = 3,
		BaseSeconds = 60,
		SecondsGrowth = 2,
		SkipGemsPerSeconds = 120,
	},

	Shield = {
		AfterLossFraction = 0.05,
		AfterLossSeconds = 3600,
		AfterWipeFraction = 0.6,
		AfterWipeSeconds = 10800,
		NewPlayerSeconds = 1800,
		BuySeconds = 86400,
		AdSeconds = 3600,
	},

	Trophies = {
		WinBase = 30,
		LevelDiffScale = 2,
		WinMin = 10,
		WinMax = 50,
		Loss = 20,
		BanditScale = 0.5, -- bandit raids award half trophies
	},

	Bandit = {
		LootPerLevel = 350,
		DecayPerRaid = 0.05,
		DecayMaxRaids = 10,
		DecayWindow = 3600,
	},

	Leagues = {
		{ name = "Wood", min = 0, weeklyGems = 10 },
		{ name = "Bronze", min = 200, weeklyGems = 25 },
		{ name = "Silver", min = 600, weeklyGems = 50 },
		{ name = "Gold", min = 1200, weeklyGems = 90 },
		{ name = "Diamond", min = 2000, weeklyGems = 150 },
		{ name = "Champion", min = 3200, weeklyGems = 250 },
	},

	Matchmaking = {
		LevelsPerBracket = 3,
		MaxCandidates = 20,
		RecentRaidCooldown = 1800, -- seconds before the same base can be raided again by anyone
		PoolTTL = 86400,
	},

	Starter = {
		Coins = 250,
		Gems = 20,
	},

	Quests = {
		PerDay = 3,
		GemsPerQuest = 10,
	},

	Group = {
		CoinBonus = 0.05,
	},
}

return Balance
