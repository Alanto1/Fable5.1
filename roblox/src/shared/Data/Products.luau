--!nonstrict
-- Products: every gamepass and developer product in one place.
-- Ids are 0 until created in Creator Hub (Monetization > Passes / Developer Products); paste
-- the real ids here and nowhere else. Prices are for display; Roblox charges the configured price.
--
-- Grant functions run on the server with (profile, player). They must be idempotent-safe: the
-- MonetizationService guarantees each receipt is granted at most once.

local Products = {
	Passes = {
		DoubleLoot = {
			id = 0,
			name = "2x Loot",
			price = 399,
			icon = "rbxassetid://0",
			description = "Every raid pays double. Permanently.",
			featured = true,
		},
		ExtraTrapSlots = {
			id = 0,
			name = "+6 Trap Slots",
			price = 299,
			icon = "rbxassetid://0",
			description = "Place six more traps and turrets in your base.",
		},
		BigVault = {
			id = 0,
			name = "Mega Vault",
			price = 199,
			icon = "rbxassetid://0",
			description = "+50% vault capacity and auto-collect from mines.",
		},
		RaidRadar = {
			id = 0,
			name = "Raid Radar",
			price = 149,
			icon = "rbxassetid://0",
			description = "See how much loot a base holds before you raid it, plus 2 free re-rolls per raid.",
		},
		VIP = {
			id = 0,
			name = "VIP",
			price = 449,
			icon = "rbxassetid://0",
			description = "VIP chat tag, golden hammer skin, exclusive base theme and +10% coins.",
		},
	},

	-- Developer products. `grant` receives (profile, player, context) and returns true on success.
	DevProducts = {
		Gems100 = { id = 0, name = "100 Gems", price = 99, gems = 100 },
		Gems550 = { id = 0, name = "550 Gems", price = 499, gems = 550, bonus = "+10%" },
		Gems1200 = { id = 0, name = "1,200 Gems", price = 999, gems = 1200, bonus = "+20%" },
		Gems3250 = { id = 0, name = "3,250 Gems", price = 2499, gems = 3250, bonus = "+30%" },
		Gems7000 = { id = 0, name = "7,000 Gems", price = 4999, gems = 7000, bonus = "+40%" },

		Shield24h = { id = 0, name = "24h Shield", price = 149, shieldSeconds = 86400 },
		StarterPack = { id = 0, name = "Starter Pack", price = 99, gems = 300, coins = 5000, oneTime = true },

		-- Rewarded video rewards are developer products too (Roblox requirement). Keep values
		-- in the 3-10 Robux range and never random.
		AdRaidKey = { id = 0, name = "Raid Key (ad)", price = 5, raidKeys = 1, adReward = true },
		AdShield1h = { id = 0, name = "1h Shield (ad)", price = 8, shieldSeconds = 3600, adReward = true },
	},
}

return Products
