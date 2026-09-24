--!nonstrict
-- Codes: promo codes. Keys are upper-case. `expires` is a unix time (0 = never).
-- Add a row, ship; the code works on the next server start.

local Codes = {
	LAUNCH = { coins = 500, gems = 25, expires = 0 },
	RAIDER = { coins = 250, gems = 10, expires = 0 },
	SHIELD = { shieldSeconds = 3600, expires = 0 },
	DISCORD = { gems = 15, expires = 0 },
}

return Codes
