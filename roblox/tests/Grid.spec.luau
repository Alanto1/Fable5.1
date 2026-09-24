--!nonstrict
local Grid = require("./.build/shared/Grid")

return function(t)
	t.case("footprint rotates", function()
		local w, d = Grid.footprintSize(2, 1, 0)
		t.eq(w, 2)
		t.eq(d, 1)
		w, d = Grid.footprintSize(2, 1, 1)
		t.eq(w, 1)
		t.eq(d, 2)
	end)

	t.case("cells enumerates footprint", function()
		local cells = Grid.cells(3, 4, 2, 2, 0)
		t.eq(#cells, 4)
		t.eq(cells[1].x, 3)
		t.eq(cells[4].z, 5)
	end)

	t.case("bounds", function()
		t.truthy(Grid.inBounds(0, 0, 1, 1, 0))
		t.truthy(Grid.inBounds(14, 14, 2, 2, 0))
		t.falsy(Grid.inBounds(15, 14, 2, 2, 0))
		t.falsy(Grid.inBounds(-1, 0, 1, 1, 0))
		t.falsy(Grid.inBounds(15, 0, 2, 1, 0))
		t.truthy(Grid.inBounds(15, 0, 2, 1, 1)) -- rotated footprint is 1 wide
	end)

	t.case("localOffset centres a footprint on its cells", function()
		local cx, cz = Grid.localOffset(0, 0, 1, 1, 0)
		t.eq(cx, -30)
		t.eq(cz, -30)
		cx, cz = Grid.localOffset(7, 7, 2, 2, 0)
		t.eq(cx, 0)
		t.eq(cz, 0)
	end)

	t.case("snap inverts localOffset", function()
		for _, case in { { 0, 0, 1, 1, 0 }, { 7, 7, 2, 2, 0 }, { 14, 3, 2, 1, 1 }, { 5, 9, 2, 2, 3 } } do
			local cx, cz = Grid.localOffset(case[1], case[2], case[3], case[4], case[5])
			local x, z = Grid.snap(cx, cz, case[3], case[4], case[5])
			t.eq(x, case[1], "x for case " .. table.concat(case, ","))
			t.eq(z, case[2], "z for case " .. table.concat(case, ","))
		end
	end)

	t.case("entrance strip", function()
		t.truthy(Grid.isEntrance(7, 15))
		t.truthy(Grid.isEntrance(6, 14))
		t.falsy(Grid.isEntrance(5, 15))
		t.falsy(Grid.isEntrance(7, 13))
		local ex, ez = Grid.entranceLocal()
		t.eq(ex, 0)
		t.eq(ez, 28)
	end)
end
