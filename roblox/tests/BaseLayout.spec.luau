--!nonstrict
local BaseLayout = require("./.build/shared/BaseLayout")
local Pieces = require("./.build/shared/Data/Pieces")

return function(t)
	t.case("starter layout is valid at level 1", function()
		local ok, err = BaseLayout.validate(BaseLayout.starter(), 1)
		t.truthy(ok, err)
	end)

	t.case("rejects two vaults and zero vaults", function()
		local layout = BaseLayout.starter()
		table.insert(layout, { id = "Vault", x = 2, z = 2, r = 0, lvl = 1 })
		local ok = BaseLayout.validate(layout, 1)
		t.falsy(ok)
		local noVault = { { id = "WallWood", x = 0, z = 0, r = 0, lvl = 1 } }
		t.falsy((BaseLayout.validate(noVault, 1)))
	end)

	t.case("rejects overlaps, entrance blocking, locked and out-of-bounds pieces", function()
		local layout = BaseLayout.starter()
		t.falsy((BaseLayout.canPlace(layout, "WallWood", 7, 5, 0, 1)), "overlap with vault")
		t.falsy((BaseLayout.canPlace(layout, "WallWood", 7, 15, 0, 1)), "entrance")
		t.falsy((BaseLayout.canPlace(layout, "WallSteel", 0, 0, 0, 1)), "locked")
		t.falsy((BaseLayout.canPlace(layout, "Fountain", 15, 0, 0, 10)), "oob")
		t.truthy((BaseLayout.canPlace(layout, "WallWood", 0, 0, 0, 1)))
	end)

	t.case("slot limits apply", function()
		local layout = BaseLayout.starter()
		local traps = Pieces.slots("Trap", 1)
		local placed = 0
		for x = 0, 15 do
			for z = 10, 13 do
				if placed < traps + 1 then
					local ok = BaseLayout.canPlace(layout, "SpikeTrap", x, z, 0, 1)
					if ok then
						table.insert(layout, { id = "SpikeTrap", x = x, z = z, r = 0, lvl = 1 })
						placed += 1
					end
				end
			end
		end
		t.eq(placed, traps, "cannot exceed trap slots")
	end)

	t.case("move ignores own cells", function()
		local layout = BaseLayout.starter()
		local _, index = BaseLayout.findVault(layout)
		t.truthy((BaseLayout.canPlace(layout, "Vault", 8, 5, 0, 1, index)), "shift vault by one")
	end)

	t.case("rating, income and capacity", function()
		local layout = BaseLayout.starter()
		t.eq(BaseLayout.rating(layout), 10 + 2 + 3)
		t.eq(BaseLayout.incomePerHour(layout), 120)
		t.eq(BaseLayout.vaultCapacity(layout), 2000)
	end)

	t.case("piece cost, hp, refund", function()
		t.eq(Pieces.cost("WallWood", 1), 25)
		t.eq(Pieces.cost("WallWood", 2), 40)
		t.eq(Pieces.hp("WallStone", 1), 300)
		t.eq(Pieces.refund("WallWood", 2), math.floor((25 + 40) * 0.5))
	end)
end
