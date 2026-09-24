--!nonstrict
-- Grid: pure maths for the base grid. Cell (0,0) is the north-west corner (min x, min z);
-- z increases toward the south edge where the entrance is. Rotation r is in quarter turns.

local Balance = require(script.Parent.Data.Balance)

local Grid = {}

Grid.Size = Balance.Grid.Size
Grid.Cell = Balance.Grid.Cell
Grid.Studs = Balance.Grid.Size * Balance.Grid.Cell -- 64

-- Footprint dimensions after rotation.
function Grid.footprintSize(w: number, d: number, r: number): (number, number)
	if r % 2 == 1 then
		return d, w
	end
	return w, d
end

-- Every cell covered by a piece placed at (x, z) with size (w, d) and rotation r.
function Grid.cells(x: number, z: number, w: number, d: number, r: number): { { x: number, z: number } }
	local fw, fd = Grid.footprintSize(w, d, r)
	local out = table.create(fw * fd)
	for dx = 0, fw - 1 do
		for dz = 0, fd - 1 do
			table.insert(out, { x = x + dx, z = z + dz })
		end
	end
	return out
end

function Grid.inBounds(x: number, z: number, w: number, d: number, r: number): boolean
	local fw, fd = Grid.footprintSize(w, d, r)
	return x >= 0 and z >= 0 and x + fw <= Grid.Size and z + fd <= Grid.Size
end

function Grid.key(x: number, z: number): string
	return x .. "," .. z
end

-- Local offset (studs) of the footprint centre from the plot centre, at ground level.
function Grid.localOffset(x: number, z: number, w: number, d: number, r: number): (number, number)
	local fw, fd = Grid.footprintSize(w, d, r)
	local half = Grid.Studs / 2
	local cx = (x + fw / 2) * Grid.Cell - half
	local cz = (z + fd / 2) * Grid.Cell - half
	return cx, cz
end

-- Snap a local position (studs from plot centre) to the top-left cell for a footprint.
function Grid.snap(localX: number, localZ: number, w: number, d: number, r: number): (number, number)
	local fw, fd = Grid.footprintSize(w, d, r)
	local half = Grid.Studs / 2
	local x = math.floor((localX + half) / Grid.Cell - fw / 2 + 0.5)
	local z = math.floor((localZ + half) / Grid.Cell - fd / 2 + 0.5)
	x = math.clamp(x, 0, Grid.Size - fw)
	z = math.clamp(z, 0, Grid.Size - fd)
	return x, z
end

function Grid.angle(r: number): number
	return (r % 4) * (math.pi / 2)
end

-- True if the cell lies in the entrance strip that must stay clear.
function Grid.isEntrance(x: number, z: number): boolean
	local e = Balance.Grid.Entrance
	return x >= e.x0 and x <= e.x1 and z >= e.z0 and z <= e.z1
end

-- Centre of the entrance strip in local studs (raiders spawn and extract here).
function Grid.entranceLocal(): (number, number)
	local e = Balance.Grid.Entrance
	local cx = ((e.x0 + e.x1 + 1) / 2) * Grid.Cell - Grid.Studs / 2
	local cz = ((e.z0 + e.z1 + 1) / 2) * Grid.Cell - Grid.Studs / 2
	return cx, cz
end

return Grid
