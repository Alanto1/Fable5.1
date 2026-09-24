--!nonstrict
-- Themes: palettes applied to every piece at render time. Colors are Color3 constructors as
-- 0-255 triplets so this file stays readable; Themes.color(theme, key) returns a Color3.

local Themes = {}

local PALETTES = {
	Classic = {
		name = "Classic",
		price = 0,
		ground = { 116, 176, 86 },
		border = { 96, 82, 64 },
		wood = { 176, 120, 66 },
		woodDark = { 120, 78, 40 },
		stone = { 150, 158, 170 },
		stoneDark = { 100, 108, 122 },
		steel = { 176, 196, 214 },
		steelDark = { 90, 110, 130 },
		titanium = { 240, 226, 190 },
		titaniumDark = { 190, 160, 100 },
		laser = { 255, 90, 200 },
		laserDark = { 120, 30, 100 },
		vault = { 255, 190, 60 },
		vaultDark = { 150, 100, 20 },
		mine = { 120, 90, 70 },
		mineAccent = { 255, 205, 60 },
		trap = { 230, 70, 70 },
		trapDark = { 120, 30, 30 },
		metal = { 70, 74, 90 },
		accent = { 80, 200, 255 },
		decor = { 90, 170, 90 },
		decorAlt = { 150, 150, 160 },
	},
	Candy = {
		name = "Candy",
		price = 500,
		ground = { 255, 200, 220 },
		border = { 190, 120, 150 },
		wood = { 255, 170, 190 },
		woodDark = { 210, 110, 140 },
		stone = { 200, 190, 240 },
		stoneDark = { 140, 120, 200 },
		steel = { 180, 240, 250 },
		steelDark = { 90, 170, 200 },
		titanium = { 255, 250, 200 },
		titaniumDark = { 220, 190, 90 },
		laser = { 255, 120, 230 },
		laserDark = { 160, 40, 140 },
		vault = { 255, 210, 90 },
		vaultDark = { 200, 130, 40 },
		mine = { 150, 90, 120 },
		mineAccent = { 255, 235, 120 },
		trap = { 255, 110, 110 },
		trapDark = { 170, 50, 60 },
		metal = { 120, 100, 140 },
		accent = { 140, 230, 255 },
		decor = { 130, 220, 150 },
		decorAlt = { 220, 180, 220 },
	},
	Neon = {
		name = "Neon",
		price = 800,
		ground = { 40, 42, 70 },
		border = { 20, 20, 40 },
		wood = { 80, 80, 130 },
		woodDark = { 40, 40, 80 },
		stone = { 60, 70, 110 },
		stoneDark = { 30, 36, 70 },
		steel = { 90, 220, 255 },
		steelDark = { 30, 120, 170 },
		titanium = { 255, 240, 120 },
		titaniumDark = { 170, 150, 40 },
		laser = { 255, 60, 220 },
		laserDark = { 130, 20, 110 },
		vault = { 255, 210, 70 },
		vaultDark = { 170, 110, 20 },
		mine = { 60, 60, 100 },
		mineAccent = { 120, 255, 200 },
		trap = { 255, 80, 120 },
		trapDark = { 140, 30, 60 },
		metal = { 40, 40, 60 },
		accent = { 120, 255, 220 },
		decor = { 120, 255, 160 },
		decorAlt = { 200, 120, 255 },
	},
	Ice = {
		name = "Ice",
		price = 800,
		ground = { 220, 240, 250 },
		border = { 150, 190, 220 },
		wood = { 170, 210, 240 },
		woodDark = { 110, 160, 210 },
		stone = { 200, 225, 245 },
		stoneDark = { 130, 170, 210 },
		steel = { 230, 245, 255 },
		steelDark = { 150, 190, 230 },
		titanium = { 250, 250, 255 },
		titaniumDark = { 190, 200, 230 },
		laser = { 130, 220, 255 },
		laserDark = { 40, 120, 180 },
		vault = { 255, 220, 120 },
		vaultDark = { 190, 140, 50 },
		mine = { 120, 150, 180 },
		mineAccent = { 255, 240, 160 },
		trap = { 255, 120, 120 },
		trapDark = { 170, 60, 70 },
		metal = { 90, 110, 140 },
		accent = { 160, 230, 255 },
		decor = { 170, 240, 220 },
		decorAlt = { 220, 230, 250 },
	},
}

Themes.Palettes = PALETTES
Themes.Order = { "Classic", "Candy", "Neon", "Ice" }

function Themes.get(name: string)
	return PALETTES[name] or PALETTES.Classic
end

function Themes.color(theme: string, key: string): Color3
	local palette = Themes.get(theme)
	local rgb = palette[key] or palette.metal
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return Themes
