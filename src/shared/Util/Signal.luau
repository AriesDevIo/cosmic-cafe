--!strict
-- Minimal synchronous signal (no Roblox dependency).

export type Connection = { disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	_handlers: { (T...) -> () },
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local self = { _handlers = {} } :: any

	function self.connect(signal: Signal<T...>, handler: (T...) -> ()): Connection
		table.insert(signal._handlers, handler)
		return {
			disconnect = function()
				local index = table.find(signal._handlers, handler)
				if index then
					table.remove(signal._handlers, index)
				end
			end,
		} :: any
	end

	function self.fire(signal: Signal<T...>, ...: T...)
		for _, handler in table.clone(signal._handlers) do
			handler(...)
		end
	end

	return self
end

return Signal
