--!nonstrict
-- BanditBases: deterministic procedural layouts so there is always something to raid.
-- Uses its own LCG so results are identical on server, client previews and in tests.

local Balance = require(script.Parent.Data.Balance)
local Pieces = require(script.Parent.Data.Pieces)
local Grid = require(script.Parent.Grid)
local BaseLayout = require(script.Parent.BaseLayout)

local BanditBases = {}

local NAMES = {
	{ min = 1, names = { "Bandit Camp", "Goblin Hideout", "Raccoon Den" } },
	{ min = 4, names = { "Pirate Cove", "Smuggler's Shack", "Fox Outpost" } },
	{ min = 8, names = { "Robo Fort", "Iron Warren", "Clockwork Keep" } },
	{ min = 13, names = { "Dragon Hoard", "Crystal Citadel", "Void Bastion" } },
}

local function lcg(seed: number)
	local state = (seed * 2654435761 + 1013904223) % 4294967296
	return {
		next = function()
			state = (state * 1664525 + 1013904223) % 4294967296
			return state / 4294967296
		end,
		int = function(min: number, max: number)
			state = (state * 1664525 + 1013904223) % 4294967296
			return min + math.floor((state / 4294967296) * (max - min + 1))
		end,
	}
end

function BanditBases.name(level: number, seed: number): string
	local pool = NAMES[1].names
	for _, band in NAMES do
		if level >= band.min then
			pool = band.names
		end
	end
	local rng = lcg(seed + 99)
	return pool[rng.int(1, #pool)] .. " Lv " .. level
end

local function wallFor(level: number): string
	if level >= 15 then
		return "WallLaser"
	elseif level >= 10 then
		return "WallTitanium"
	elseif level >= 6 then
		return "WallSteel"
	elseif level >= 3 then
		return "WallStone"
	end
	return "WallWood"
end

local function tryAdd(layout, occ, id, x, z, r, lvl): boolean
	local def = Pieces.get(id)
	if not def or not Grid.inBounds(x, z, def.size.w, def.size.d, r) then
		return false
	end
	for _, cell in Grid.cells(x, z, def.size.w, def.size.d, r) do
		if occ[Grid.key(cell.x, cell.z)] or Grid.isEntrance(cell.x, cell.z) then
			return false
		end
	end
	for _, cell in Grid.cells(x, z, def.size.w, def.size.d, r) do
		occ[Grid.key(cell.x, cell.z)] = true
	end
	table.insert(layout, { id = id, x = x, z = z, r = r, lvl = lvl })
	return true
end

-- Generates a valid layout for a bandit base of `level`. Difficulty scales: a ring of walls
-- around the vault with a gap, traps on the approach, turrets and guards at higher levels.
function BanditBases.generate(level: number, seed: number)
	level = math.clamp(level, 1, Balance.XP.MaxLevel)
	local rng = lcg(seed + level * 7919)
	local layout = {}
	local occ = {}

	-- Vault somewhere in the north half.
	local vx = rng.int(4, 10)
	local vz = rng.int(2, 6)
	local vaultLevel = math.max(1, math.min(20, math.floor(level / 2) + 1))
	tryAdd(layout, occ, "Vault", vx, vz, 0, vaultLevel)

	-- Ring of walls around the vault, radius grows with level, one or two gaps.
	local wall = wallFor(level)
	local wallLevel = math.clamp(1 + level // 6, 1, 5)
	local radius = 2 + math.min(3, level // 4)
	local gapSide = rng.int(0, 3)
	local gapAt = rng.int(0, 1)
	for dx = -radius, radius + 1 do
		for dz = -radius, radius + 1 do
			local onEdge = dx == -radius or dx == radius + 1 or dz == -radius or dz == radius + 1
			if onEdge then
				local side = if dz == radius + 1
					then 0
					elseif dx == radius + 1 then 1
					elseif dz == -radius then 2
					else 3
				local isGap = side == gapSide and math.abs((dx + dz) % 3) == gapAt
				if not isGap then
					tryAdd(layout, occ, wall, vx + dx, vz + dz, 0, wallLevel)
				end
			end
		end
	end

	-- Mines inside the ring.
	local mines = math.min(6, 1 + level // 2)
	local placedMines = 0
	for _ = 1, 40 do
		if placedMines >= mines then
			break
		end
		local x = vx + rng.int(-radius + 1, radius)
		local z = vz + rng.int(-radius + 1, radius)
		if tryAdd(layout, occ, "Mine", x, z, 0, math.max(1, level // 2)) then
			placedMines += 1
		end
	end

	-- Traps between the entrance and the ring, biased toward the gap side.
	local trapPool = { "SpikeTrap" }
	if level >= 2 then
		table.insert(trapPool, "Flinger")
	end
	if level >= 4 then
		table.insert(trapPool, "FlameJet")
	end
	if level >= 5 then
		table.insert(trapPool, "FreezePad")
	end
	if level >= 7 then
		table.insert(trapPool, "Pit")
	end
	if level >= 8 then
		table.insert(trapPool, "BearTrap")
	end
	local traps = math.min(Pieces.slots("Trap", level), 1 + level)
	local placedTraps = 0
	local trapLevel = math.clamp(1 + level // 5, 1, 8)
	for _ = 1, 80 do
		if placedTraps >= traps then
			break
		end
		local id = trapPool[rng.int(1, #trapPool)]
		local x = rng.int(2, 13)
		local z = rng.int(vz + radius + 2, 13)
		if tryAdd(layout, occ, id, x, z, rng.int(0, 3), trapLevel) then
			placedTraps += 1
		end
	end

	-- Turrets on the ring corners at higher levels.
	local turrets = Pieces.slots("Turret", level)
	if turrets > 0 then
		local turretPool = { "Cannon" }
		if level >= 9 then
			table.insert(turretPool, "Zapper")
		end
		if level >= 12 then
			table.insert(turretPool, "GooGun")
		end
		local corners = {
			{ vx - radius - 1, vz + radius + 2 },
			{ vx + radius + 2, vz + radius + 2 },
			{ vx - radius - 1, vz - radius - 1 },
			{ vx + radius + 2, vz - radius - 1 },
		}
		for i = 1, math.min(turrets, 4) do
			local id = turretPool[rng.int(1, #turretPool)]
			tryAdd(layout, occ, id, corners[i][1], corners[i][2], 0, math.clamp(1 + level // 6, 1, 10))
		end
	end

	-- Guards near the gap.
	local guards = Pieces.slots("Guard", level)
	for i = 1, math.min(guards, 4) do
		local id = (level >= 11 and i % 2 == 0) and "GuardDog" or "GuardBot"
		for _ = 1, 20 do
			local x = vx + rng.int(-radius - 2, radius + 3)
			local z = vz + rng.int(radius + 1, radius + 4)
			if tryAdd(layout, occ, id, x, z, 0, math.clamp(1 + level // 6, 1, 10)) then
				break
			end
		end
	end

	-- A few decor pieces for personality.
	for _ = 1, rng.int(2, 5) do
		local id = ({ "Bush", "Rock", "Torch", "Flag" })[rng.int(1, 4)]
		tryAdd(layout, occ, id, rng.int(0, 15), rng.int(0, 15), rng.int(0, 3), 1)
	end

	-- Guarantee validity by dropping anything a lower-level base could not hold.
	local ok = BaseLayout.validate(layout, level)
	if not ok then
		-- Fall back to a minimal valid layout; should not happen, but never ship an invalid base.
		layout = BaseLayout.starter()
	end
	return layout
end

-- Loot the bandit vault holds, before decay.
function BanditBases.storedFor(level: number): number
	return Balance.Bandit.LootPerLevel * level * 4 -- 25% of this is stealable per raid
end

return BanditBases
