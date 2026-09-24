--!nonstrict
-- Make: declarative instance creation.
--   Make("Frame", { Size = ..., Parent = gui, [1] = Make("TextLabel", {...}), Activated = fn })
-- Numeric keys are children, event names connect functions, everything else sets a property.

local function Make(className: string, props)
	local instance = Instance.new(className)
	local children = nil
	local parent = nil
	for key, value in props do
		if type(key) == "number" then
			children = children or {}
			table.insert(children, value)
		elseif key == "Parent" then
			parent = value
		elseif key == "Children" then
			children = children or {}
			for _, child in value do
				table.insert(children, child)
			end
		elseif type(value) == "function" then
			local signal = instance[key]
			if typeof(signal) == "RBXScriptSignal" then
				signal:Connect(value)
			else
				error(("Make: %s.%s is not an event"):format(className, key))
			end
		else
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return Make
