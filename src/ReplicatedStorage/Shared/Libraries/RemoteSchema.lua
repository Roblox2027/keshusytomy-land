--!strict
--[[
	RemoteSchema
	Esquema de los canales remotos y validacion de forma del payload.

	Se separa de RemoteGateway a proposito: es logica PURA, sin
	servicios de Roblox, por lo que puede ejecutarse en pruebas de
	verdad (luau.exe / TestEZ) sin montar un servidor.

	Este modulo NO decide si la accion es legal para el jugador
	(nivel, propiedad, saldo). Eso lo hace cada servicio receptor.
	Aqui solo se filtra la FORMA y el RANGO de lo que llega.
]]

-- GameConstants NO se requiere aqui a proposito.
--
-- En Roblox, `require` con `script.Parent` funciona; en el interprete
-- de pruebas (luau.exe) `script` no existe y las rutas de `require`
-- se resuelven desde el archivo que llama, no desde este modulo.
-- Como no existe una ruta que sea correcta en ambos entornos, el
-- mapa de canales se INYECTA desde el consumidor:
--
--     local Schema = RemoteSchema.new(GameConstants.RemoteAction)
--
-- Ventaja adicional: el modulo queda como logica pura, sin ninguna
-- dependencia, y por tanto es 100% testeable.

local Schema = {}

Schema.PayloadType = {
	None = "Ninguno",
	Boolean = "Boolean",
	Number = "Numero",
	String = "Cadena",
	Vector3 = "Vector3",
	Table = "Tabla",
}

--- Crea un esquema a partir del mapa de canales.
--- @param remoteAction { [string]: string }
--- @return table schema
function Schema.new(remoteAction: { [string]: string })
	assert(type(remoteAction) == "table", "RemoteSchema.new requiere GameConstants.RemoteAction")

	local PayloadType = Schema.PayloadType

	-- Esquema: canal -> accion -> tipo esperado del payload.
	local schemaByChannel: { [string]: { [string]: string } } = {
		[remoteAction.Player] = {
			RequestState = PayloadType.None,
			SetReady = PayloadType.Boolean,
		},
		[remoteAction.Bomb] = {
			Place = PayloadType.Vector3,
		},
		[remoteAction.Shop] = {
			Preview = PayloadType.String,
			Purchase = PayloadType.String,
		},
		[remoteAction.Inventory] = {
			Equip = PayloadType.String,
			Unequip = PayloadType.String,
		},
		[remoteAction.Quest] = {
			Claim = PayloadType.String,
			-- Sin payload: el dia y la racha los decide el servidor a
			-- partir de su reloj y del perfil. Aceptarlos del cliente
			-- permitiria reclamar el diario sin esperar.
			ClaimDaily = PayloadType.None,
		},
		-- El canje de codigos. El payload es el TEXTO que el jugador
		-- escribio, nunca la recompensa: si el cliente mandara la
		-- recompensa, el servidor tendria que fiarse de el y cualquier
		-- exploit pagaria lo que quisiera.
		--
		-- El tipo declarado es `String`, y `ValidatePayload` ya exige que
		-- no tenga caracteres especiales ni sea mas larga de 64. Eso no
		-- es un limite arbitrario: `CodeRules.Normalize` rechaza cualquier
		-- cosa que no sea alfanumerica, asi que el filtro del gateway y el
		-- de las reglas coinciden. Si divergieran, el jugador veria
		-- "codigo mal formado" para un texto que el gateway habria
		-- dejado pasar.
		[remoteAction.Code] = {
			Redeem = PayloadType.String,
		},
		[remoteAction.Portal] = {
			Enter = PayloadType.String,
		},
		[remoteAction.Core] = {
			-- Sin payload: el nucleo no acepta ninguna cifra del cliente.
			-- Si se declarara un numero, el cliente podria intentar
			-- "aportar 9999" y el servidor tendria que fiarse de el.
			Interact = PayloadType.None,
			RequestState = PayloadType.None,
		},
		[remoteAction.Party] = {
			Create = PayloadType.None,
			Invite = PayloadType.Number,
			Accept = PayloadType.Number,
			Decline = PayloadType.Number,
			Leave = PayloadType.None,
			Kick = PayloadType.Number,
			ToggleReady = PayloadType.None,
		},
		[remoteAction.Settings] = {
			SetVolume = PayloadType.Table,
			SetQuality = PayloadType.String,
		},
		-- Combate cuerpo a cuerpo (mision V2). SIN payload a proposito:
		-- el cliente no manda objetivo, ni distancia, ni paso de combo.
		-- Todo eso lo decide el servidor; aqui solo se pide actuar.
		[remoteAction.Combat] = {
			Melee = PayloadType.None,
			Dash = PayloadType.None,
			Ability = PayloadType.None,
		},
	}

	local self = {
		Schema = schemaByChannel,
		PayloadType = PayloadType,
	}

	--- Acciones permitidas en un canal.
	--- @param channel string
	--- @return { [string]: string }
	function self.GetActions(self, channel: string): { [string]: string }
		return schemaByChannel[channel] or {}
	end

	--- Indica si una accion existe en el esquema del canal.
	--- @param channel string
	--- @param action string
	--- @return boolean
	function self.HasAction(self, channel: string, action: string): boolean
		local actions = schemaByChannel[channel]
		return actions ~= nil and actions[action] ~= nil
	end

	--- Indica si el canal existe en el esquema.
	--- @param channel string
	--- @return boolean
	function self.HasChannel(self, channel: string): boolean
		return schemaByChannel[channel] ~= nil
	end

	--- Tipo declarado para una accion, o nil si no existe.
	--- @param channel string
	--- @param action string
	--- @return string?
	function self.GetPayloadType(self, channel: string, action: string): string?
		local actions = schemaByChannel[channel]
		if not actions then
			return nil
		end
		return actions[action]
	end

	return self
end

--- Valida las componentes de una posicion enviada por el cliente.
---
--- Se separa de ValidatePayload porque, fuera del motor de Roblox,
--- el tipo Vector3 no expone sus componentes de la misma forma.
--- Asi el RANGO permitido se prueba de verdad con numeros simples.
---
--- Regla de seguridad: una posicion solo es aceptable si es finita
--- y esta dentro del mundo. Una magnitud absurda indica un intento
--- de mover al jugador fuera del mapa o de romper la fisica.
--- @param x number
--- @param y number
--- @param z number
--- @param magnitude number
--- @return boolean valid
--- @return string? reason
function Schema.ValidateVectorComponents(
	x: number,
	y: number,
	z: number,
	magnitude: number
): (boolean, string?)
	local MAX_COMPONENT = 1e6

	if x ~= x or y ~= y or z ~= z or magnitude ~= magnitude then
		return false, "componente no finito"
	end

	if
		math.abs(x) > MAX_COMPONENT
		or math.abs(y) > MAX_COMPONENT
		or math.abs(z) > MAX_COMPONENT
	then
		return false, "componente fuera de rango"
	end

	if magnitude > MAX_COMPONENT then
		return false, "Vector3 fuera de rango"
	end

	if magnitude == math.huge or magnitude == -math.huge then
		return false, "Vector3 fuera de rango"
	end

	return true
end

--- Valida la FORMA del payload. No valida permisos ni negocio.
---
--- Funcion pura y sin estado: valida contra `Schema.PayloadType`.
--- @param expectedType string
--- @param payload any
--- @return boolean valid
--- @return string? reason
function Schema.ValidatePayload(expectedType: string, payload: any): (boolean, string?)
	local PayloadType = Schema.PayloadType
	local payloadType = typeof(payload)

	if expectedType == PayloadType.None then
		if payload ~= nil then
			return false, "no se esperaba payload"
		end
		return true
	end

	if expectedType == PayloadType.Boolean then
		if payloadType ~= "boolean" then
			return false, "se esperaba Boolean"
		end
		return true
	end

	if expectedType == PayloadType.Number then
		if payloadType ~= "number" then
			return false, "se esperaba Numero"
		end
		-- NaN / infinito rompen la aritmetica del servidor.
		if payload ~= payload or payload == math.huge or payload == -math.huge then
			return false, "numero no finito"
		end
		return true
	end

	if expectedType == PayloadType.String then
		if payloadType ~= "string" then
			return false, "se esperaba Cadena"
		end
		-- Los ids son tokens cortos y estables: sin espacios, sin
		-- caracteres de control y sin AttemptToInject.
		if #payload == 0 or #payload > 64 then
			return false, "longitud de cadena invalida"
		end
		if payload:match("[^%w_%-]") then
			return false, "caracteres no permitidos"
		end
		return true
	end

	if expectedType == PayloadType.Vector3 then
		if payloadType ~= "Vector3" then
			return false, "se esperaba Vector3"
		end
		return Schema.ValidateVectorComponents(payload.X, payload.Y, payload.Z, payload.Magnitude)
	end

	if expectedType == PayloadType.Table then
		if payloadType ~= "table" then
			return false, "se esperaba Tabla"
		end
		-- Una tabla con millones de claves agota memoria del servidor.
		local count = 0
		for _ in payload do
			count += 1
			if count > 32 then
				return false, "tabla demasiado grande"
			end
		end
		return true
	end

	return false, "tipo de esquema desconocido: " .. tostring(expectedType)
end

return Schema
