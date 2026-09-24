--!nonstrict
-- Lune test runner for pure shared modules (no Roblox engine needed).
--   lune run tests/run.luau
-- Each *.spec.luau file returns a function(t) and registers cases with t.case(name, fn).

local fs = require("@lune/fs")
local process = require("@lune/process")

local specs = {}
for _, name in fs.readDir("tests") do
	if name:match("%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

local passed, failed = 0, 0
local failures = {}

local function makeT(specName)
	local t = {}
	function t.case(caseName, fn)
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print(("  ok   %s / %s"):format(specName, caseName))
		else
			failed += 1
			table.insert(failures, ("%s / %s: %s"):format(specName, caseName, tostring(err)))
			print(("  FAIL %s / %s\n       %s"):format(specName, caseName, tostring(err)))
		end
	end
	function t.eq(actual, expected, label)
		if actual ~= expected then
			error(
				("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)),
				2
			)
		end
	end
	function t.truthy(value, label)
		if not value then
			error(("%s: expected truthy, got %s"):format(label or "value", tostring(value)), 2)
		end
	end
	function t.falsy(value, label)
		if value then
			error(("%s: expected falsy, got %s"):format(label or "value", tostring(value)), 2)
		end
	end
	function t.near(actual, expected, tolerance, label)
		if math.abs(actual - expected) > (tolerance or 1e-6) then
			error(
				("%s: expected ~%s, got %s"):format(label or "value", tostring(expected), tostring(actual)),
				2
			)
		end
	end
	return t
end

for _, name in specs do
	print(name)
	local spec = require("./" .. name:gsub("%.luau$", ""))
	spec(makeT(name))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	for _, failure in failures do
		print("  " .. failure)
	end
	process.exit(1)
end
