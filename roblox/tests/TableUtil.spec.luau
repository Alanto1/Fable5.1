--!nonstrict
local TableUtil = require("./.build/shared/Util/TableUtil")

return function(t)
	t.case("deepCopy produces an independent copy", function()
		local original = { a = 1, nested = { b = { 1, 2, 3 } } }
		local copy = TableUtil.deepCopy(original)
		copy.nested.b[1] = 99
		t.eq(original.nested.b[1], 1)
		t.eq(copy.a, 1)
	end)

	t.case("reconcile fills missing keys without clobbering existing ones", function()
		local template = { Coins = 0, Settings = { Music = true, Sfx = true }, Inventory = {} }
		local saved = { Coins = 500, Settings = { Music = false } }
		TableUtil.reconcile(saved, template)
		t.eq(saved.Coins, 500)
		t.eq(saved.Settings.Music, false)
		t.eq(saved.Settings.Sfx, true)
		t.truthy(saved.Inventory)
	end)

	t.case("reconcile does not merge into arrays", function()
		local template = { List = { "a", "b" } }
		local saved = { List = { "x" } }
		TableUtil.reconcile(saved, template)
		t.eq(#saved.List, 1)
		t.eq(saved.List[1], "x")
	end)

	t.case("weightedPick respects weights", function()
		-- Stub rng with the same surface as Roblox's Random (not available in Lune).
		local seed = 7
		local rng = {}
		function rng:NextNumber()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		function rng:NextInteger(min, max)
			return min + math.floor(self:NextNumber() * (max - min + 1))
		end
		local entries = { { weight = 0, value = "never" }, { weight = 1, value = "always" } }
		for _ = 1, 50 do
			t.eq(TableUtil.weightedPick(entries, rng), "always")
		end
		local counts = { a = 0, b = 0 }
		local skewed = { { weight = 9, value = "a" }, { weight = 1, value = "b" } }
		for _ = 1, 2000 do
			local pick = TableUtil.weightedPick(skewed, rng)
			counts[pick] += 1
		end
		t.truthy(counts.a > counts.b * 5, "9:1 weights should pick a far more often")
	end)

	t.case("count/keys/values/filter/map", function()
		local tbl = { a = 1, b = 2, c = 3 }
		t.eq(TableUtil.count(tbl), 3)
		t.eq(#TableUtil.keys(tbl), 3)
		t.eq(#TableUtil.values(tbl), 3)
		local evens = TableUtil.filter({ 1, 2, 3, 4 }, function(v)
			return v % 2 == 0
		end)
		t.eq(#evens, 2)
		local doubled = TableUtil.map({ 1, 2 }, function(v)
			return v * 2
		end)
		t.eq(doubled[2], 4)
	end)
end
