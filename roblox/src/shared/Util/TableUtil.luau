--!nonstrict
-- TableUtil: copying, reconciliation and small helpers used by data and config code.

local TableUtil = {}

function TableUtil.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = TableUtil.deepCopy(item)
	end
	return copy
end

-- Fills missing keys in `target` from `template` (recursively for tables). Never removes keys,
-- so old saves survive template growth. Array-like tables are copied wholesale when missing.
function TableUtil.reconcile(target, template)
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.deepCopy(templateValue)
		elseif type(templateValue) == "table" and type(current) == "table" and #templateValue == 0 then
			TableUtil.reconcile(current, templateValue)
		end
	end
	return target
end

function TableUtil.count(tbl)
	local n = 0
	for _ in tbl do
		n += 1
	end
	return n
end

function TableUtil.keys(tbl)
	local out = {}
	for key in tbl do
		table.insert(out, key)
	end
	return out
end

function TableUtil.values(tbl)
	local out = {}
	for _, value in tbl do
		table.insert(out, value)
	end
	return out
end

function TableUtil.map(list, fn)
	local out = table.create(#list)
	for index, value in list do
		out[index] = fn(value, index)
	end
	return out
end

function TableUtil.filter(list, fn)
	local out = {}
	for index, value in list do
		if fn(value, index) then
			table.insert(out, value)
		end
	end
	return out
end

function TableUtil.find(list, fn)
	for index, value in list do
		if fn(value, index) then
			return value, index
		end
	end
	return nil
end

function TableUtil.shuffle(list, rng)
	rng = rng or Random.new()
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function TableUtil.merge(...)
	local out = {}
	for i = 1, select("#", ...) do
		local tbl = select(i, ...)
		if tbl then
			for key, value in tbl do
				out[key] = value
			end
		end
	end
	return out
end

-- Weighted pick: entries = { {weight = n, value = any}, ... }
function TableUtil.weightedPick(entries, rng)
	rng = rng or Random.new()
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in entries do
		roll -= entry.weight
		if roll <= 0 then
			return entry.value
		end
	end
	return entries[#entries].value
end

function TableUtil.freeze(tbl)
	for _, value in tbl do
		if type(value) == "table" and not table.isfrozen(value) then
			TableUtil.freeze(value)
		end
	end
	return table.freeze(tbl)
end

return TableUtil
