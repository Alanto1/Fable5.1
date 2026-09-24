--!nonstrict
local BanditBases = require("./.build/shared/BanditBases")
local BaseLayout = require("./.build/shared/BaseLayout")

return function(t)
	t.case("generates valid layouts for every level", function()
		for level = 1, 30 do
			for seed = 1, 6 do
				local layout = BanditBases.generate(level, seed)
				local ok, err = BaseLayout.validate(layout, level)
				t.truthy(ok, ("level %d seed %d: %s"):format(level, seed, tostring(err)))
				t.truthy(#layout >= 5, "has several pieces")
			end
		end
	end)

	t.case("is deterministic", function()
		local a = BanditBases.generate(9, 123)
		local b = BanditBases.generate(9, 123)
		t.eq(#a, #b)
		for i, piece in a do
			t.eq(piece.id, b[i].id)
			t.eq(piece.x, b[i].x)
			t.eq(piece.z, b[i].z)
		end
	end)

	t.case("difficulty grows with level", function()
		local low = BaseLayout.rating(BanditBases.generate(2, 5))
		local high = BaseLayout.rating(BanditBases.generate(20, 5))
		t.truthy(high > low * 3, ("rating %d vs %d"):format(low, high))
	end)

	t.case("names are stable and level-tagged", function()
		local name = BanditBases.name(6, 42)
		t.eq(name, BanditBases.name(6, 42))
		t.truthy(name:find("Lv 6", 1, true))
	end)
end
