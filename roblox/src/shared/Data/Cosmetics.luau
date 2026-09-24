--!nonstrict
-- Cosmetics: hammer skins, sack skins and trails. Purely visual, gem-priced or pass-granted.

local Cosmetics = {
	Hammers = {
		Classic = { name = "Classic Hammer", price = 0, head = { 120, 120, 130 }, handle = { 150, 100, 60 } },
		Gold = {
			name = "Golden Hammer",
			price = 0,
			pass = "VIP",
			head = { 255, 200, 60 },
			handle = { 200, 140, 30 },
			glow = true,
		},
		Candy = { name = "Candy Hammer", price = 150, head = { 255, 120, 180 }, handle = { 255, 230, 240 } },
		Void = {
			name = "Void Hammer",
			price = 400,
			head = { 40, 20, 60 },
			handle = { 120, 60, 200 },
			glow = true,
		},
		Lava = {
			name = "Lava Hammer",
			price = 600,
			head = { 255, 90, 30 },
			handle = { 60, 30, 30 },
			glow = true,
		},
		Ice = {
			name = "Ice Hammer",
			price = 400,
			head = { 180, 230, 255 },
			handle = { 240, 250, 255 },
			glow = true,
		},
		Banana = { name = "Banana Hammer", price = 800, head = { 255, 230, 70 }, handle = { 200, 170, 40 } },
	},

	Sacks = {
		Classic = { name = "Burlap Sack", price = 0, color = { 170, 130, 80 } },
		Velvet = { name = "Velvet Sack", price = 150, color = { 120, 40, 90 } },
		Gold = { name = "Gold Sack", price = 400, color = { 255, 200, 60 }, glow = true },
		Loot = { name = "Loot Bag", price = 300, color = { 40, 40, 50 } },
	},

	Trails = {
		None = { name = "None", price = 0 },
		Sparkle = { name = "Sparkle", price = 100, color = { 255, 240, 180 } },
		Coins = { name = "Coin Trail", price = 250, color = { 255, 200, 60 } },
		Frost = { name = "Frost", price = 300, color = { 160, 230, 255 } },
		Flame = { name = "Flame", price = 400, color = { 255, 120, 40 } },
		Rainbow = { name = "Rainbow", price = 600, rainbow = true },
	},
}

function Cosmetics.get(kind: string, key: string)
	local bucket = Cosmetics[kind]
	return bucket and bucket[key] or nil
end

return Cosmetics
