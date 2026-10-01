--!strict
--[[
	Maid
	Limpieza de recursos con ciclo de vida explicito.

	Objetivo: que ninguna conexion, hilo, instancia o callback
	creado por el juego quede vivo sin un `Destroy` correspondiente.

	Se usa igual en servidor y cliente, y no depende de ningun
	servicio de Roblox, por lo que es 100% testeable de forma aislada.

	Uso:
		local maid = Maid.new()
		maid:Add(connection)          -- se desconecta al destruir
		maid:Add(instance)            -- se destruye al destruir
		maid:Add(fn)                  -- se llama al destruir
		maid:Destroy()
]]

export type Cleanup = (() -> ())

local Maid = {}
Maid.__index = Maid

-- Aviso portable: `warn` existe en Roblox pero no en el interprete
-- de pruebas, por lo que no se puede llamar directo.
local function warnSafe(message: string)
	if type(warn) == "function" then
		warn(message)
	else
		print(message)
	end
end

--- Crea un Maid vacio.
--- @return Maid
function Maid.new(): Maid
	local self = setmetatable({}, Maid)
	self._cleanups = {}
	self._count = 0
	self._isDestroyed = false
	return self
end

--- Indica si el Maid ya fue destruido.
--- @return boolean
function Maid:IsDestroyed(): boolean
	return self._isDestroyed
end

--- Cantidad de recursos registrados.
--- @return number
function Maid:Count(): number
	return self._count
end

--- Marca un recurso como pendiente de limpieza.
--- @param value any recurso: RBXScriptConnection | Instance | Cleanup | { [any]: any }
--- @return any value devuelve el mismo valor, para encadenar
function Maid:Add(value: any): any
	if value == nil then
		return nil
	end

	if self._isDestroyed then
		-- Destruir tarde sigue siendo seguro: el recurso se libera ya.
		Maid._release(value)
		return value
	end

	self._count += 1
	self._cleanups[self._count] = value
	return value
end

--- Libera un recurso de forma inmediata y lo elimina del Maid.
--- @param value any
--- @return boolean released si estaba registrado
function Maid:Remove(value: any): boolean
	for index = 1, self._count do
		if self._cleanups[index] == value then
			table.remove(self._cleanups, index)
			self._count -= 1
			Maid._release(value)
			return true
		end
	end
	return false
end

--- Crea (y registra) una conexion de evento ya conectada.
--- @param signal RBXScriptSignal
--- @param callback (...any) -> ()
--- @return RBXScriptConnection? connection nil si el Maid ya estaba destruido
function Maid:Connect(signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection?
	if self._isDestroyed then
		return nil
	end

	local connection = signal:Connect(callback)
	self._count += 1
	self._cleanups[self._count] = connection
	return connection
end

--- Crea un hilo con task.delay ya registrado.
--- @param seconds number
--- @param callback () -> ()
--- @return thread? spawned nil si el Maid ya estaba destruido
function Maid:Delay(seconds: number, callback: () -> ()): thread?
	if self._isDestroyed then
		return nil
	end

	local spawned = task.delay(seconds, function()
		self:Remove(spawned)
		callback()
	end)

	self._count += 1
	self._cleanups[self._count] = spawned
	return spawned
end

--- Ejecuta los callbacks registrados sin destruir los recursos.
--- Sirve para reiniciar un ciclo manteniendo el Maid vivo.
function Maid:DoCallbacks()
	local snapshot = table.clone(self._cleanups)

	for index = 1, #snapshot do
		local value = snapshot[index]
		if type(value) == "function" then
			local ok, err = pcall(value)
			if not ok then
				error(("Maid callback fallo: %s"):format(tostring(err)), 0)
			end
		end
	end
end

--- Libera todos los recursos. Es idempotente y nunca lanza errores.
function Maid:Destroy()
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	local cleanups = self._cleanups
	self._cleanups = {}
	local count = self._count
	self._count = 0

	for index = count, 1, -1 do
		Maid._release(cleanups[index])
	end
end

--- Libera un recurso concreto tolerando cualquier forma admitida.
--- @param value any
function Maid._release(value: any)
	if value == nil then
		return
	end

	local valueType = type(value)

	if valueType == "function" then
		local ok, err = pcall(value)
		if not ok then
			warnSafe(("Maid cleanup fallo: %s"):format(tostring(err)))
		end
		return
	end

	if valueType == "thread" then
		if coroutine.status(value) == "suspended" then
			pcall(task.cancel, value)
		end
		return
	end

	if valueType == "table" then
		-- Tabla de recursos (pool o lista): se libera cada elemento.
		-- Se evita la recursion infinita con tablas autorreferentes.
		if not value[Maid] then
			value[Maid] = true
			for _, nested in value do
				Maid._release(nested)
			end
			value[Maid] = nil
		end
		return
	end

	-- Instances y userdata de Roblox (RBXScriptConnection, etc.).
	-- Se comprueba la existencia del metodo: es portable y no depende
	-- de `typeof`, que no existe fuera del motor de Roblox.
	if valueType == "Instance" or valueType == "userdata" then
		local index = value.__index

		if type(index) == "table" or type(index) == "function" then
			if type(value.Destroy) == "function" then
				pcall(value.Destroy, value)
				return
			end
			if type(value.Disconnect) == "function" then
				pcall(value.Disconnect, value)
				return
			end
		end
		return
	end
end

return Maid