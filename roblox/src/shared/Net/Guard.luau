--!nonstrict
-- Guard: composable runtime validators for remote arguments.
-- Every remote handler declares guards; anything that fails is dropped before game code runs.

local Guard = {}

function Guard.any()
	return function()
		return true
	end
end

function Guard.number(min: number?, max: number?)
	return function(value)
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return false
		end
		if min and value < min then
			return false
		end
		if max and value > max then
			return false
		end
		return true
	end
end

function Guard.integer(min: number?, max: number?)
	local numberGuard = Guard.number(min, max)
	return function(value)
		return numberGuard(value) and math.floor(value) == value
	end
end

function Guard.string(maxLength: number?)
	return function(value)
		return type(value) == "string" and (maxLength == nil or #value <= maxLength)
	end
end

function Guard.boolean()
	return function(value)
		return type(value) == "boolean"
	end
end

function Guard.enum(options: { string })
	local set = {}
	for _, option in options do
		set[option] = true
	end
	return function(value)
		return type(value) == "string" and set[value] == true
	end
end

function Guard.keyOf(tbl)
	return function(value)
		return type(value) == "string" and tbl[value] ~= nil
	end
end

function Guard.optional(inner)
	return function(value)
		return value == nil or inner(value)
	end
end

function Guard.vector3(maxMagnitude: number?)
	return function(value)
		if typeof(value) ~= "Vector3" then
			return false
		end
		if value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z then
			return false
		end
		return maxMagnitude == nil or value.Magnitude <= maxMagnitude
	end
end

function Guard.cframe()
	return function(value)
		return typeof(value) == "CFrame"
	end
end

function Guard.instance(className: string?)
	return function(value)
		return typeof(value) == "Instance" and (className == nil or value:IsA(className))
	end
end

-- Strict table shape: every declared key must pass, no undeclared keys allowed.
function Guard.shape(shape)
	return function(value)
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if shape[key] == nil then
				return false
			end
		end
		for key, guard in shape do
			if not guard(value[key]) then
				return false
			end
		end
		return true
	end
end

function Guard.array(itemGuard, maxLength: number?)
	return function(value)
		if type(value) ~= "table" then
			return false
		end
		local count = 0
		for key, item in value do
			count += 1
			if type(key) ~= "number" or key ~= count or not itemGuard(item) then
				return false
			end
		end
		return maxLength == nil or count <= maxLength
	end
end

function Guard.check(guards, ...)
	local argCount = select("#", ...)
	if argCount > #guards then
		return false, "too many arguments"
	end
	for index, guard in guards do
		local value = select(index, ...)
		if not guard(value) then
			return false, "argument " .. index .. " rejected"
		end
	end
	return true
end

return Guard
