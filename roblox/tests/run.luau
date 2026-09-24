--!nonstrict
-- Lune test runner for pure shared modules (no Roblox engine needed).
--   lune run tests/run.luau
--
-- Roblox modules require siblings as `require(script.Parent.Data.Balance)`. Lune has no `script`,
-- so src/shared is mirrored into tests/.build/shared with those requires rewritten to relative
-- string requires. Specs require modules from the mirror.
-- Each *.spec.luau file returns a function(t) and registers cases with t.case(name, fn).

local fs = require("@lune/fs")
local process = require("@lune/process")

local SRC = "src/shared"
local OUT = "tests/.build/shared"

local function rewriteRequires(source: string): string
	return (
		source:gsub("require%(script(%.Parent[%.%w_]*)%)", function(path: string)
			local segments = {}
			for segment in path:gmatch("%.([%w_]+)") do
				table.insert(segments, segment)
			end
			local ups = 0
			while segments[1] == "Parent" do
				table.remove(segments, 1)
				ups += 1
			end
			local prefix = ups <= 1 and "./" or string.rep("../", ups - 1)
			return ('require("%s%s")'):format(prefix, table.concat(segments, "/"))
		end)
	)
end

local function mirror(dir: string, out: string)
	if fs.isDir(out) then
		fs.removeDir(out)
	end
	fs.writeDir(out)
	for _, name in fs.readDir(dir) do
		local from = dir .. "/" .. name
		local to = out .. "/" .. name
		if fs.isDir(from) then
			mirror(from, to)
		elseif name:match("%.luau$") then
			fs.writeFile(to, rewriteRequires(fs.readFile(from)))
		end
	end
end

mirror(SRC, OUT)

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
