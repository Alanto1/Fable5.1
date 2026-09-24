--!nonstrict
-- Signal: a small event primitive with RBXScriptSignal semantics.
-- Handlers run in their own thread so a slow or yielding handler never blocks the firer.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	if signal._head == self then
		signal._head = self._next
	else
		local prev = signal._head
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

function Signal.new()
	return setmetatable({ _head = nil }, Signal)
end

function Signal:Connect(handler)
	local connection = setmetatable({
		Connected = true,
		_handler = handler,
		_signal = self,
		_next = self._head,
	}, Connection)
	self._head = connection
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	local connection = self._head
	while connection do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
		connection = connection._next
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	local connection = self._head
	while connection do
		connection.Connected = false
		connection = connection._next
	end
	self._head = nil
end

return Signal
