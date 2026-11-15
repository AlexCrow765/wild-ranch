--!strict
--[[
	Signal
	Minimal in-process event used for communication between services/controllers
	on the same side of the network (never across client/server - use Net/Remotes).

	local changed = Signal.new()
	local conn = changed:Connect(function(value) print(value) end)
	changed:Fire(5)
	conn:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local listeners: { { callback: (...any) -> (), connection: Connection } } = {}
	local self = {} :: Signal

	local function remove(connection: Connection)
		for index, entry in listeners do
			if entry.connection == connection then
				table.remove(listeners, index)
				break
			end
		end
	end

	function self:Connect(callback: (...any) -> ()): Connection
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			if self.Connected then
				self.Connected = false
				remove(self)
			end
		end
		table.insert(listeners, { callback = callback, connection = connection })
		return connection
	end

	function self:Once(callback: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function self:Wait(): ...any
		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self:Fire(...: any)
		-- Copy so listeners can safely disconnect while we iterate.
		for _, entry in table.clone(listeners) do
			if entry.connection.Connected then
				task.spawn(entry.callback, ...)
			end
		end
	end

	function self:DisconnectAll()
		for _, entry in listeners do
			entry.connection.Connected = false
		end
		table.clear(listeners)
	end

	return self
end

return Signal
