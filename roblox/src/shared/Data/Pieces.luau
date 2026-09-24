--!nonstrict
-- Pieces: the catalog of everything that can be placed on a base.
-- Adding a piece = adding a row here + a model from tools/gen_props.py. Systems never hard-code ids
-- except "Vault" and "Mine".

local Balance = require(script.Parent.Balance)

local Pieces = {}

-- Ordered so shop tabs and unlock lists read naturally.
local LIST = {
	-- Structures
	{
		id = "Vault",
		name = "Vault",
		category = "Structure",
		size = { w = 2, d = 2 },
		cost = 0,
		unlock = 1,
		hp = 400,
		hpGrowth = 1.35,
		rating = 10,
		maxLevel = 20,
		height = 6,
		description = "Holds the coins your mines make. Raiders crack it to steal 25% of what is inside.",
		stats = { capacity = Balance.Vault.BaseCapacity },
		growth = { capacity = Balance.Vault.CapacityGrowth },
		sellable = false,
	},
	{
		id = "Mine",
		name = "Coin Mine",
		category = "Structure",
		size = { w = 1, d = 1 },
		cost = 150,
		unlock = 1,
		hp = 120,
		rating = 2,
		maxLevel = 15,
		height = 4,
		description = "Makes coins every hour, even while you are away. Smashing it drops a little loot.",
		stats = { income = Balance.Mine.BaseIncome },
		growth = { income = Balance.Mine.IncomeGrowth },
	},

	-- Walls
	{
		id = "WallWood",
		name = "Wood Wall",
		category = "Wall",
		size = { w = 1, d = 1 },
		cost = 25,
		unlock = 1,
		hp = 100,
		rating = 1,
		maxLevel = 5,
		height = 5,
		description = "Cheap and cheerful. Two hammer swings.",
		stats = {},
		growth = {},
	},
	{
		id = "WallStone",
		name = "Stone Wall",
		category = "Wall",
		size = { w = 1, d = 1 },
		cost = 100,
		unlock = 3,
		hp = 300,
		rating = 2,
		maxLevel = 5,
		height = 5,
		description = "Solid. Slows down any raider without a big hammer.",
		stats = {},
		growth = {},
	},
	{
		id = "WallSteel",
		name = "Steel Wall",
		category = "Wall",
		size = { w = 1, d = 1 },
		cost = 400,
		unlock = 6,
		hp = 800,
		rating = 4,
		maxLevel = 5,
		height = 5,
		description = "Shiny and stubborn.",
		stats = {},
		growth = {},
	},
	{
		id = "WallTitanium",
		name = "Titanium Wall",
		category = "Wall",
		size = { w = 1, d = 1 },
		cost = 1600,
		unlock = 10,
		hp = 2000,
		rating = 7,
		maxLevel = 5,
		height = 5,
		description = "Raiders will need a plan, not a hammer.",
		stats = {},
		growth = {},
	},
	{
		id = "WallLaser",
		name = "Laser Wall",
		category = "Wall",
		size = { w = 1, d = 1 },
		cost = 6400,
		unlock = 15,
		hp = 5000,
		rating = 12,
		maxLevel = 5,
		height = 5,
		description = "Hums menacingly. Almost unbreakable.",
		stats = {},
		growth = {},
	},

	-- Traps
	{
		id = "SpikeTrap",
		name = "Spike Trap",
		category = "Trap",
		size = { w = 1, d = 1 },
		cost = 150,
		unlock = 1,
		hp = 60,
		rating = 3,
		maxLevel = 8,
		height = 1,
		description = "Pops when stepped on. Hurts and stuns.",
		stats = { damage = 25, stun = 0.6, rearm = 2.0 },
		growth = { damage = 1.12 },
	},
	{
		id = "Flinger",
		name = "Flinger",
		category = "Trap",
		size = { w = 1, d = 1 },
		cost = 400,
		unlock = 2,
		hp = 80,
		rating = 5,
		maxLevel = 8,
		height = 1,
		description = "Launches raiders into the sky. Great for clips.",
		stats = { force = 55, rearm = 3.0 },
		growth = { force = 1.08 },
	},
	{
		id = "FlameJet",
		name = "Flame Jet",
		category = "Trap",
		size = { w = 1, d = 1 },
		cost = 600,
		unlock = 4,
		hp = 80,
		rating = 6,
		maxLevel = 8,
		height = 1,
		description = "Two seconds of fire, three seconds of rest. Time it.",
		stats = { onTime = 2, offTime = 3, tickDamage = 8, tickRate = 0.5 },
		growth = { tickDamage = 1.12 },
	},
	{
		id = "FreezePad",
		name = "Freeze Pad",
		category = "Trap",
		size = { w = 1, d = 1 },
		cost = 500,
		unlock = 5,
		hp = 60,
		rating = 5,
		maxLevel = 8,
		height = 1,
		description = "Slows raiders to a crawl for a few seconds.",
		stats = { slow = 0.3, duration = 3, rearm = 1 },
		growth = { duration = 1.1 },
	},
	{
		id = "Pit",
		name = "Trapdoor Pit",
		category = "Trap",
		size = { w = 2, d = 2 },
		cost = 900,
		unlock = 7,
		hp = 150,
		rating = 8,
		maxLevel = 8,
		height = 1,
		description = "Drops raiders in a hole. Climbing out takes time and spills coins.",
		stats = { climb = 4, spill = 0.2 },
		growth = { climb = 1.08 },
	},
	{
		id = "BearTrap",
		name = "Bear Trap",
		category = "Trap",
		size = { w = 1, d = 1 },
		cost = 700,
		unlock = 8,
		hp = 60,
		rating = 6,
		maxLevel = 8,
		height = 1,
		description = "Roots the raider in place. Watch the clock tick.",
		stats = { root = 2.5, damage = 15, rearm = 4 },
		growth = { root = 1.08, damage = 1.1 },
	},

	-- Turrets
	{
		id = "Cannon",
		name = "Cannon Turret",
		category = "Turret",
		size = { w = 1, d = 1 },
		cost = 1200,
		unlock = 6,
		hp = 200,
		rating = 9,
		maxLevel = 10,
		height = 5,
		description = "Slow shells that knock raiders back.",
		stats = { range = 30, damage = 30, cooldown = 2.5, projectileSpeed = 40, knockback = 30 },
		growth = { damage = 1.12, range = 1.03 },
	},
	{
		id = "Zapper",
		name = "Zapper",
		category = "Turret",
		size = { w = 1, d = 1 },
		cost = 2000,
		unlock = 9,
		hp = 200,
		rating = 11,
		maxLevel = 10,
		height = 5,
		description = "Arcs lightning between nearby raiders and slows them.",
		stats = { range = 12, slow = 0.5, duration = 2, cooldown = 3, damage = 10 },
		growth = { damage = 1.12, duration = 1.06 },
	},
	{
		id = "GooGun",
		name = "Goo Gun",
		category = "Turret",
		size = { w = 1, d = 1 },
		cost = 3000,
		unlock = 12,
		hp = 200,
		rating = 12,
		maxLevel = 10,
		height = 5,
		description = "Leaves sticky puddles that slow anyone who steps in.",
		stats = { range = 24, cooldown = 3, puddleSlow = 0.5, puddleLife = 6 },
		growth = { puddleLife = 1.08 },
	},

	-- Guards
	{
		id = "GuardBot",
		name = "Guard Bot",
		category = "Guard",
		size = { w = 1, d = 1 },
		cost = 1500,
		unlock = 5,
		hp = 250,
		rating = 10,
		maxLevel = 10,
		height = 6,
		description = "Patrols and chases anyone it sees.",
		stats = { speed = 14, damage = 20, leash = 24, attackRange = 4.5, cooldown = 1.2 },
		growth = { damage = 1.12, speed = 1.03 },
	},
	{
		id = "GuardDog",
		name = "Guard Dog",
		category = "Guard",
		size = { w = 1, d = 1 },
		cost = 2500,
		unlock = 11,
		hp = 180,
		rating = 12,
		maxLevel = 10,
		height = 3,
		description = "Fast. Bites the sack and spills coins.",
		stats = { speed = 20, damage = 8, spill = 0.05, leash = 30, attackRange = 4, cooldown = 1.5 },
		growth = { damage = 1.1, speed = 1.02 },
	},

	-- Decor (rating 0, cosmetic)
	{
		id = "Flag",
		name = "Flag",
		category = "Decor",
		size = { w = 1, d = 1 },
		cost = 50,
		unlock = 1,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 8,
		description = "Plant your colours.",
		stats = {},
		growth = {},
	},
	{
		id = "Torch",
		name = "Torch",
		category = "Decor",
		size = { w = 1, d = 1 },
		cost = 80,
		unlock = 1,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 5,
		description = "Warm light for cold nights.",
		stats = {},
		growth = {},
	},
	{
		id = "Bush",
		name = "Bush",
		category = "Decor",
		size = { w = 1, d = 1 },
		cost = 60,
		unlock = 2,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 3,
		description = "Hides traps nicely.",
		stats = {},
		growth = {},
	},
	{
		id = "Rock",
		name = "Rock",
		category = "Decor",
		size = { w = 1, d = 1 },
		cost = 60,
		unlock = 2,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 3,
		description = "It is a rock.",
		stats = {},
		growth = {},
	},
	{
		id = "Statue",
		name = "Statue",
		category = "Decor",
		size = { w = 1, d = 1 },
		cost = 300,
		unlock = 5,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 7,
		description = "A monument to your greed.",
		stats = {},
		growth = {},
	},
	{
		id = "Fountain",
		name = "Fountain",
		category = "Decor",
		size = { w = 2, d = 2 },
		cost = 500,
		unlock = 8,
		hp = 40,
		rating = 0,
		maxLevel = 1,
		height = 5,
		description = "Fancy. Raiders will be jealous.",
		stats = {},
		growth = {},
	},
}

Pieces.List = LIST
Pieces.ById = {}
Pieces.ByCategory = {}
Pieces.Categories = { "Structure", "Wall", "Trap", "Turret", "Guard", "Decor" }

for _, def in LIST do
	def.costGrowth = def.costGrowth or 1.6
	def.hpGrowth = def.hpGrowth or 1.25
	def.sellable = def.sellable ~= false
	Pieces.ById[def.id] = def
	Pieces.ByCategory[def.category] = Pieces.ByCategory[def.category] or {}
	table.insert(Pieces.ByCategory[def.category], def)
end

function Pieces.get(id: string)
	return Pieces.ById[id]
end

-- Cost to buy at level 1, or to upgrade *to* `level`.
function Pieces.cost(id: string, level: number): number
	local def = Pieces.ById[id]
	if not def then
		return math.huge
	end
	if level <= 1 then
		return def.cost
	end
	return math.floor(def.cost * def.costGrowth ^ (level - 1))
end

function Pieces.hp(id: string, level: number): number
	local def = Pieces.ById[id]
	return math.floor(def.hp * def.hpGrowth ^ (level - 1))
end

function Pieces.rating(id: string, level: number): number
	local def = Pieces.ById[id]
	return def.rating * level
end

function Pieces.stat(id: string, level: number, key: string): number
	local def = Pieces.ById[id]
	local base = def.stats[key]
	if base == nil then
		return 0
	end
	local growth = def.growth[key]
	if growth then
		return base * growth ^ (level - 1)
	end
	return base
end

-- Sell refund for a piece at a level: half of everything spent on it.
function Pieces.refund(id: string, level: number): number
	local total = 0
	for l = 1, level do
		total += Pieces.cost(id, l)
	end
	return math.floor(total * 0.5)
end

-- How many pieces of a category a base may hold at a given base level.
function Pieces.slots(category: string, baseLevel: number): number
	if category == "Structure" then
		return 1 -- the vault; mines are counted separately
	elseif category == "Mine" then
		return math.min(6, 1 + baseLevel // 2)
	elseif category == "Wall" then
		return 20 + 4 * baseLevel
	elseif category == "Trap" then
		return 2 + baseLevel
	elseif category == "Turret" then
		return baseLevel // 3
	elseif category == "Guard" then
		return baseLevel // 5
	elseif category == "Decor" then
		return 10 + baseLevel
	end
	return 0
end

-- Slot key used for counting: mines are their own bucket, other structures share "Structure".
function Pieces.slotKey(id: string): string
	if id == "Mine" then
		return "Mine"
	end
	return Pieces.ById[id].category
end

return Pieces
