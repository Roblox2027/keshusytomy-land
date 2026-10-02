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
	---
	--- Recibe la instancia como parametro (no la captura) para que la tabla
	--- que se esta construyendo no quede referenciada a si misma. `clock` se
	--- lee de la tabla viva en cada llamada.
	---
	--- @param instance any la instancia del limitador
	--- @param key string
	--- @return any bucket
	local function refill(instance, key)
		local self = instance
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

	--- Normaliza el receptor de los metodos publicos.
	---
	--- BUG CORREGIDO (auditoria de integracion)
	--- ----------------------------------------
	--- `TryConsume`, `GetTokens`, `Reset` y `Clear` se declaraban como
	--- METODOS (`function self.X(self, ...)`) pero TODOS los llamantes los
	--- invocaban con PUNTO: `limiter.TryConsume(clave)`.
	---
	--- Con punto, el primer parametro declarado recibe el ARGUMENTO en lugar de
	--- la instancia. Adentro, `self` era la clave (un string) y `key` era `nil`,
	--- de modo que `self.clock()` era `(string).clock()` y reventaba con
	--- "attempt to call a nil value", y `Clear` fallaba con "attempt to index
	--- nil with 'buckets'".
	---
	--- Esos mensajes no senalaban la causa, y el fallo solo aparecia la PRIMERA
	--- vez que se consumia un token. Las pruebas del modulo no lo detectaban
	--- porque el `RateLimiter.spec` las invoca con dos puntos; el primero que
	--- lo llamo con punto fue el remoto de portales, en el vertical slice.
	---
	--- La solucion NO es cambiar los llamantes (eso dejaria la trampa puesta
	--- para el siguiente) sino que este metodo acepte las DOS convenciones: si
	--- el primer argumento no es la instancia, se busca en la upvalue `self`.
	---
	--- @param first any lo que llego como primer argumento
	--- @param second any el segundo argumento, si hubo
	--- @return any instance siempre la upvalue: no hay ambiguedad posible
	--- @return any key la clave, este sea el estilo de llamada
	--- @return any cost el coste, o nil si no se paso
	local function resolveReceiver(first, second, third)
		if first == self then
			-- Llamada con dos puntos: (instancia, clave, coste).
			return self, second, third
		end
		-- Llamada con punto: (clave, coste).
		return self, first, second
	end

	--- Intenta consumir un token. Devuelve false si se agoto.
	--- @param key string
	--- @param cost number?
	--- @return boolean allowed
	function self.TryConsume(first: any, second: any, third: any): boolean
		local instance, realKey, realCost = resolveReceiver(first, second, third)
		local spend = tonumber(realCost) or 1

		if spend <= 0 then
			return true
		end

		local bucket = refill(instance, realKey)
		if bucket.tokens < spend then
			return false
		end

		bucket.tokens -= spend
		return true
	end

	--- Tokens disponibles actualmente para una clave.
	--- @param key string
	--- @return number
	function self.GetTokens(first: any, second: any): number
		local instance, realKey = resolveReceiver(first, second)
		return refill(instance, realKey).tokens
	end

	--- Restablece una clave (por ejemplo al desconectar el jugador).
	--- @param key string
	function self.Reset(first: any, second: any)
		local instance, realKey = resolveReceiver(first, second)
		instance.buckets[realKey] = nil
	end

	--- Elimina todas las claves. Se usa en el cierre del servidor.
	function self.Clear(...)
		-- `Clear` no recibe clave, asi que basta con localizar la instancia
		-- entre los argumentos: con punto no llega ninguno y con dos puntos
		-- llega el receptor.
		local first = ...
		local instance = self
		if first ~= nil and first ~= self and type(first) == "table" then
			instance = first
		end
		table.clear(instance.buckets)
	end

	return self
end

return RateLimiter