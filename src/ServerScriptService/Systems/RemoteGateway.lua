--!strict
--[[
	RemoteGateway
	Unica puerta de entrada para los RemoteEvent del servidor.

	Por que existe (FASE 1):
	El cliente NUNCA es autoridad. Todo lo que llega por un remoto es
	una entrada NO CONFIABLE y pasa siempre por esta cadena:

		1. ?El servidor esta aceptando trabajo?
		2. ?El emisor es realmente un jugador conectado?
		3. ?El canal esta registrado en este gateway?
		4. ?La accion solicitada esta permitida en el esquema?
		5. ?La frecuencia es aceptable (rate limit)?
		6. ?Los argumentos coinciden con el esquema (tipos/rangos)?

	Solo si las 6 validaciones pasan se ejecuta el handler.

	Regla: el esquema declara QUE se espera; nunca "confia en lo que
	dijo el cliente". El handler sigue validando la logica de negocio
	(nivel, propiedad, saldo). Aqui solo se filtra la forma.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))
local RateLimiter = require(SHARED:WaitForChild("Libraries"):WaitForChild("RateLimiter"))
local RemoteSchemaLib = require(SHARED:WaitForChild("Libraries"):WaitForChild("RemoteSchema"))
local Maid = require(SHARED:WaitForChild("Libraries"):WaitForChild("Maid"))

local RemoteAction = GameConstants.RemoteAction

-- El esquema vive en Shared/Libraries/RemoteSchema.lua (logica pura y
-- testeable). Aqui solo se conecta el transporte y se aplica el
-- limite de frecuencia.

export type Handler = (player: Player, payload: any) -> ()

local Gateway = {}
Gateway.__index = Gateway

Gateway.Name = "RemoteGateway"

Gateway._handlers = {}
Gateway._channels = {}
Gateway._maid = nil
Gateway._limiter = nil
Gateway._rejected = {}

--- Crea el gateway.
--- @param options { capacity: number?, refillPerSecond: number? }?
--- @return table
function Gateway.new(options: { capacity: number?, refillPerSecond: number? }?)
	-- El `or {}` de abajo NECESITA anotacion explicita. Sin ella Luau
-- unnests la union `{...}? | {}` y `resolved` queda tipado como `{}`,
-- de modo que `resolved.capacity` es un acceso a una clave inexistente
-- en un tipo cerrado: el analizador lo marca como error aunque en
-- ejecucion la clave exista. La anotacion mantiene el tipo real sin
-- cambiar una sola linea de comportamiento.
local resolved: { capacity: number?, refillPerSecond: number? } = options or {}
	local self = setmetatable({
		_handlers = {},
		_channels = {},
		_rejected = {},
		_maid = nil,
		_isRunning = false,
		-- Logica pura y validable de forma independiente.
		_schema = RemoteSchemaLib.new(RemoteAction),
	}, Gateway)

	-- Token bucket por jugador: frena el spam sin bloquear rafagas normales.
	self._limiter = RateLimiter.new({
		capacity = resolved.capacity or 10,
		refillPerSecond = resolved.refillPerSecond or 10,
	})

	return self
end

--- Declara un canal valido y conecta su handler.
--- @param channelName string debe existir en ReplicatedStorage.Remotes
--- @param handlers { [string]: Handler }
--- @return boolean success
--- @return string? errorMessage
function Gateway:Register(channelName: string, handlers: { [string]: Handler }): (boolean, string?)
	if self._channels[channelName] then
		return false, ("canal ya registrado: %s"):format(channelName)
	end

	local schema = self._schema:GetActions(channelName)
	if next(schema) == nil then
		Logger.Error(("canal '%s' no tiene esquema declarado en RemoteSchema"):format(channelName))
		return false, ("canal sin esquema: %s"):format(channelName)
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild(channelName)

	if not remote or not remote:IsA("RemoteEvent") then
		Logger.Warn(("Remote '%s' no encontrado en ReplicatedStorage.Remotes"):format(channelName))
		return false, ("remote inexistente: %s"):format(channelName)
	end

	for action in pairs(handlers) do
		if not schema[action] then
			Logger.Error(("accion '%s' no permitida en el canal '%s'"):format(action, channelName))
			return false, ("accion no permitida: %s"):format(action)
		end
		self._handlers[channelName .. "." .. action] = handlers[action]
	end

	self._channels[channelName] = schema
	return true
end

--- Registra los canales definidos en GameConstants.RemoteAction.
--- @param handlers { [string]: { [string]: Handler } }
--- @return { string } canales registrados
function Gateway:RegisterDefaults(handlers: { [string]: { [string]: Handler } }): { string }
	local registered = {}

	for channelName, channelHandlers in handlers do
		local ok = self:Register(channelName, channelHandlers)
		if ok then
			table.insert(registered, channelName)
		end
	end

	return registered
end
--- Valida la forma del payload delegando en el esquema compartido.
--- @param expectedType string
--- @param payload any
--- @return boolean valid
--- @return string? reason
function Gateway:_ValidatePayload(expectedType: string, payload: any): (boolean, string?)
	return RemoteSchemaLib.ValidatePayload(expectedType, payload)
end

--- Registra el rechazo para diagnostico, con limite de tasa de logs.
--- @param key string
--- @param reason string
function Gateway:_RecordRejection(key: string, reason: string)
	local now = os.clock()
	local windowStart = self._rejected._windowStart or now

	if now - windowStart > 60 then
		self._rejected = { _windowStart = now }
		windowStart = now
	end

	self._rejected[key] = (self._rejected[key] or 0) + 1

	-- Solo se avisa una vez por clave y ventana: evita log flooding
	-- por parte de un cliente que spamea.
	if self._rejected[key] == 1 then
		Logger.Warn(("remote rechazado [%s]: %s"):format(key, reason))
	end
end

--- Puntos de entrada generico. Nunca se expone a clientes.
function Gateway:_OnRemote(channelName: string)
	local schema = self._channels[channelName]

	return function(player: Player, action: any, payload: any)
		-- 1. El servidor acepta trabajo.
		if not self._isRunning then
			return
		end

		-- 2. El emisor debe ser un jugador real conectado a este servidor.
		-- No se deduce de los argumentos: se verifica contra Players.
		if type(player) ~= "userdata" or not player.Parent then
			return
		end
		if Players:GetPlayerByUserId(player.UserId) ~= player then
			self:_RecordRejection("emisor", "emisor no es un jugador conectado")
			return
		end

		-- 3/4. Accion conocida en el esquema.
		if typeof(action) ~= "string" then
			return
		end

		local expectedType = schema[action]
		if not expectedType then
			self:_RecordRejection(("action:%s"):format(channelName), ("accion invalida: %s"):format(action))
			return
		end

		local handler = self._handlers[channelName .. "." .. action]

		-- 5. Limite de frecuencia por jugador.
		local limitKey = ("%d:%s.%s"):format(player.UserId, channelName, action)
		if not self._limiter.TryConsume(limitKey) then
			self:_RecordRejection(("rate:%s"):format(limitKey), "supera el limite de frecuencia")
			return
		end

		-- 6. Forma del payload.
		local valid, reason = self:_ValidatePayload(expectedType, payload)
		if not valid then
			self:_RecordRejection(("payload:%s"):format(limitKey), tostring(reason))
			return
		end

		if not handler then
			-- Accion permitida por esquema pero todavia sin handler.
			Logger.Debug(("sin handler para %s.%s"):format(channelName, action))
			return
		end

		-- El handler nunca debe tumbar el servidor por datos del cliente.
		local ok, err = pcall(handler, player, payload)
		if not ok then
			Logger.Error(("handler %s.%s fallo: %s"):format(channelName, action, tostring(err)))
		end
	end
end
--- Conecta todas las conexiones de los canales registrados.
--- @param maid any Maid con el que se limpiara todo
function Gateway:Start(maid: any)
	if self._maid then
		return
	end

	self._maid = maid or Maid.new()
	self._isRunning = true

	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	for channelName in pairs(self._channels) do
		local remote = remotes:FindFirstChild(channelName)
		if remote and remote:IsA("RemoteEvent") then
			self._maid:Connect(remote.OnServerEvent, self:_OnRemote(channelName))
		end
	end

	-- Limpia el estado del rate limiter cuando un jugador sale.
	-- Sin esto, los buckets de un jugador que se fue quedarian
	-- vivos durante toda la vida del servidor (fuga de memoria).
	self._maid:Connect(Players.PlayerRemoving, function(player: Player)
		self:ResetPlayerLimits(player.UserId)
	end)

	Logger.Info(("RemoteGateway: %d canales validados y conectados"):format(self:GetChannelCount()))
end

--- Elimina todos los limites de frecuencia de un jugador.
--- @param userId number
function Gateway:ResetPlayerLimits(userId: number)
	local prefix = tostring(userId) .. ":"
	local stale = {}

	for key in self._limiter.buckets do
		if key:sub(1, #prefix) == prefix then
			table.insert(stale, key)
		end
	end

	for _, key in stale do
		self._limiter.Reset(key)
	end
end

--- Cantidad de canales registrados.
--- @return number
function Gateway:GetChannelCount(): number
	local count = 0
	for _ in pairs(self._channels) do
		count += 1
	end
	return count
end

--- Estadisticas de rechazos (diagnostico / anti-exploit).
--- @return number
function Gateway:GetRejectedCount(): number
	local total = 0
	for key, value in pairs(self._rejected) do
		if key ~= "_windowStart" then
			total += value
		end
	end
	return total
end

--- Detiene el gateway: deja de aceptar trabajo nuevo.
function Gateway:Stop()
	self._isRunning = false

	if self._maid then
		pcall(function()
			self._maid:Destroy()
		end)
	end

	self._limiter.Clear()
	self._rejected = {}
end

return Gateway