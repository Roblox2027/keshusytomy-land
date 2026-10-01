--!strict
--[[
	RateLimiter
	Limitacion de frecuencia (token bucket) para entradas no confiables.

	El cliente es una entrada no confiable: puede enviar cientos de
	peticiones por segundo. Este modulo las limita por "clave"
	(normalmente `userId .. ":" .. accion`) antes de que lleguen a
	cualquier sistema de juego.

	Caracteristicas:
	- Token bucket: tolera rafagas cortas pero frena el abuso sostenido.
	- `Reset` al desconectar para no arrastrar estado.
	- No depende de servicios de Roblox: el reloj es inyectable y en
	  las pruebas se controla manualmente (determinismo).

	Regla de seguridad: un limite rechazando NUNCA concede nada.
	El servidor sigue validando authorizes aunque el limite pase.
]]

local RateLimiter = {}

export type RateLimiterOptions = {
	-- Tokens iniciales disponibles al crear la clave.
	capacity: number,
	-- Tokens que se regeneran por segundo.
	refillPerSecond: number,
	-- Reloj inyectable (os.clock por defecto). Facilita las pruebas.
	clock: () -> number,
}

export type Bucket = {
	tokens: number,
	lastRefill: number,
}

--- Crea un limitador.
--- @param options RateLimiterOptions?
--- @return table
function RateLimiter.new(options: RateLimiterOptions?)
	local resolved = options or ({} :: RateLimiterOptions)
	local capacity = resolved.capacity or 5
	local refillPerSecond = resolved.refillPerSecond or 5

	assert(capacity > 0, "RateLimiter: capacity debe ser mayor que 0")
	assert(refillPerSecond > 0, "RateLimiter: refillPerSecond debe ser mayor que 0")

	local self = {
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		clock = resolved.clock or (function(): number
			return os.clock()
		end),
		buckets = {},
	}

	--- Regenera los tokens de una clave segun el tiempo transcurrido.
	--- @param key string
	--- @return Bucket
	local function refill(self, key)
		local now = self.clock()
		local bucket = self.buckets[key]

		if not bucket then
			bucket = { tokens = self.capacity, lastRefill = now }
			self.buckets[key] = bucket
			return bucket
		end

		local elapsed = now - bucket.lastRefill
		if elapsed > 0 then
			bucket.tokens = math.min(self.capacity, bucket.tokens + (elapsed * self.refillPerSecond))
			bucket.lastRefill = now
		end

		return bucket
	end

	--- Intenta consumir un token. Devuelve false si se agoto.
	--- @param key string
	--- @param cost number?
	--- @return boolean allowed
	function self.TryConsume(self, key: string, cost: number?): boolean
		local spend = cost or 1
		if spend <= 0 then
			return true
		end

		local bucket = refill(self, key)
		if bucket.tokens < spend then
			return false
		end

		bucket.tokens -= spend
		return true
	end

	--- Tokens disponibles actualmente para una clave.
	--- @param key string
	--- @return number
	function self.GetTokens(self, key: string): number
		return refill(self, key).tokens
	end

	--- Restablece una clave (por ejemplo al desconectar el jugador).
	--- @param key string
	function self.Reset(self, key: string)
		self.buckets[key] = nil
	end

	--- Elimina todas las claves. Se usa en el cierre del servidor.
	function self.Clear(self)
		table.clear(self.buckets)
	end

	return self
end

return RateLimiter