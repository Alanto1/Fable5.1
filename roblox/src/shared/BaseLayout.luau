--!nonstrict
-- BaseLayout: pure validation and maths over a layout.
-- A layout is an array of pieces: { id = "WallWood", x = 3, z = 4, r = 0, lvl = 1 }.

local Balance = require(script.Parent.Data.Balance)
local Pieces = require(script.Parent.Data.Pieces)
local Grid = require(script.Parent.Grid)

local BaseLayout = {}

export type Piece = { id: string, x: number, z: number, r: number, lvl: number }
export type Layout = { Piece }

local function isInteger(n): boolean
	return type(n) == "number" and n == n and math.floor(n) == n
end

function BaseLayout.isPieceShape(piece): boolean
	return type(piece) == "table"
		and type(piece.id) == "string"
		and isInteger(piece.x)
		and isInteger(piece.z)
		and isInteger(piece.r)
		and isInteger(piece.lvl)
		and piece.r >= 0
		and piece.r <= 3
		and piece.lvl >= 1
end

-- Map "x,z" -> piece index for every occupied cell.
function BaseLayout.occupancy(layout: Layout): { [string]: number }
	local occ = {}
	for index, piece in layout do
		local def = Pieces.get(piece.id)
		if def then
			for _, cell in Grid.cells(piece.x, piece.z, def.size.w, def.size.d, piece.r) do
				occ[Grid.key(cell.x, cell.z)] = index
			end
		end
	end
	return occ
end

function BaseLayout.counts(layout: Layout): { [string]: number }
	local counts = {}
	for _, piece in layout do
		local key = Pieces.slotKey(piece.id)
		counts[key] = (counts[key] or 0) + 1
	end
	return counts
end

function BaseLayout.rating(layout: Layout): number
	local total = 0
	for _, piece in layout do
		if Pieces.get(piece.id) then
			total += Pieces.rating(piece.id, piece.lvl)
		end
	end
	return total
end

function BaseLayout.findVault(layout: Layout): (Piece?, number?)
	for index, piece in layout do
		if piece.id == "Vault" then
			return piece, index
		end
	end
	return nil, nil
end

-- Can `id` be placed at (x, z, r) given the current layout and base level? `ignoreIndex` lets a
-- move ignore the piece's own cells.
function BaseLayout.canPlace(
	layout: Layout,
	id: string,
	x: number,
	z: number,
	r: number,
	baseLevel: number,
	ignoreIndex: number?
): (boolean, string?)
	local def = Pieces.get(id)
	if not def then
		return false, "unknown piece"
	end
	if def.unlock > baseLevel then
		return false, "locked"
	end
	if not Grid.inBounds(x, z, def.size.w, def.size.d, r) then
		return false, "out of bounds"
	end
	local occ = BaseLayout.occupancy(layout)
	for _, cell in Grid.cells(x, z, def.size.w, def.size.d, r) do
		if Grid.isEntrance(cell.x, cell.z) then
			return false, "entrance must stay clear"
		end
		local other = occ[Grid.key(cell.x, cell.z)]
		if other and other ~= ignoreIndex then
			return false, "occupied"
		end
	end
	if ignoreIndex == nil then
		local counts = BaseLayout.counts(layout)
		local key = Pieces.slotKey(id)
		local used = counts[key] or 0
		if id == "Vault" and used >= 1 then
			return false, "only one vault"
		end
		if used >= Pieces.slots(key, baseLevel) then
			return false, "no slots left"
		end
	end
	return true
end

-- Full validation for a stored layout. Returns ok, reason.
function BaseLayout.validate(layout, baseLevel: number): (boolean, string?)
	if type(layout) ~= "table" then
		return false, "layout not a table"
	end
	if #layout > 200 then
		return false, "too many pieces"
	end
	local occ = {}
	local counts = {}
	local vaults = 0
	for index, piece in layout do
		if not BaseLayout.isPieceShape(piece) then
			return false, "bad piece at " .. index
		end
		local def = Pieces.get(piece.id)
		if not def then
			return false, "unknown piece " .. tostring(piece.id)
		end
		if piece.lvl > def.maxLevel then
			return false, "level too high at " .. index
		end
		if def.unlock > baseLevel then
			return false, "locked piece " .. piece.id
		end
		if not Grid.inBounds(piece.x, piece.z, def.size.w, def.size.d, piece.r) then
			return false, "out of bounds at " .. index
		end
		for _, cell in Grid.cells(piece.x, piece.z, def.size.w, def.size.d, piece.r) do
			local key = Grid.key(cell.x, cell.z)
			if occ[key] then
				return false, "overlap at " .. key
			end
			if Grid.isEntrance(cell.x, cell.z) then
				return false, "entrance blocked at " .. key
			end
			occ[key] = index
		end
		local slotKey = Pieces.slotKey(piece.id)
		counts[slotKey] = (counts[slotKey] or 0) + 1
		if piece.id == "Vault" then
			vaults += 1
		end
	end
	if vaults ~= 1 then
		return false, "layout needs exactly one vault"
	end
	for slotKey, used in counts do
		if used > Pieces.slots(slotKey, baseLevel) then
			return false, "too many " .. slotKey
		end
	end
	return true
end

-- Starter base: vault near the north, one mine, three wood walls in front of the vault.
function BaseLayout.starter(): Layout
	return {
		{ id = "Vault", x = 7, z = 5, r = 0, lvl = 1 },
		{ id = "Mine", x = 5, z = 6, r = 0, lvl = 1 },
		{ id = "WallWood", x = 7, z = 8, r = 0, lvl = 1 },
		{ id = "WallWood", x = 8, z = 8, r = 0, lvl = 1 },
		{ id = "WallWood", x = 6, z = 8, r = 0, lvl = 1 },
	}
end

-- Total mine income per hour for a layout.
function BaseLayout.incomePerHour(layout: Layout): number
	local total = 0
	for _, piece in layout do
		if piece.id == "Mine" then
			total += Pieces.stat("Mine", piece.lvl, "income")
		end
	end
	return total
end

function BaseLayout.vaultCapacity(layout: Layout): number
	local vault = BaseLayout.findVault(layout)
	if not vault then
		return Balance.Vault.BaseCapacity
	end
	return math.floor(Pieces.stat("Vault", vault.lvl, "capacity"))
end

function BaseLayout.clone(layout: Layout): Layout
	local out = table.create(#layout)
	for index, piece in layout do
		out[index] = { id = piece.id, x = piece.x, z = piece.z, r = piece.r, lvl = piece.lvl }
	end
	return out
end

return BaseLayout
