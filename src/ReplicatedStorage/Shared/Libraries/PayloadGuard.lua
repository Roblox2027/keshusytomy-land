--!strict
--[[
	PayloadGuard
	Saneamiento y rechazo de payloads remotos no confiables.

	POR QUE EXISTE (y por que no dentro de RemoteSchema)
	------------------------------------------------------
	`RemoteSchema` filtra la FORMA declarada por cada accion (un Vector3,
	una cadena, un booleano). Eso es necesario, pero no alcanza: el
	cliente puede mandar cualquier cosa por un canal que si acepta ese
	tipo, y hay tipos que `RemoteSchema` no cubre porque solo aparecen
	en ataques:

	  - `NaN` e `Infinity`: NO son numeros utilizables. `tonumber` los
	    acepta, las comparaciones con ellos son falsas y un `NaN` pasado
	    a un contador rompe la aritmetica para siempre.
	  - cadenas gigantes: ocupan memoria y pueden acabar en un log.
	  - profundidad de tabla anidada: recorre el servidor entero.
	  - tipos que no son los declarados: se rechazan, no se "interpretan".

	Este modulo es logica PURA (sin servicios de Roblox) para poder PROBAR
	cada vector de ataque sin montar un servidor. Es la diferencia entre
	"el gateway deberia rechazarlo" y "esta probado que lo rechaza".

	REGLA INNEGOCIABLE
	-----------------
	Un rechazo NUNCA concede, NUNCA modifica estado y NUNCA castea el
	valor. Devuelve `false` y un motivo legible. Sanear en silencio
	(truncar, clampear) se prohibe aqui a proposito: si un cliente manda
	999999999 de monedas, "arreglarlo" a un numero razonable significaria
	que el servidor ha inventado un valor que el cliente pidio.
]]

local Guard = {}

--- Tamano maximo admitido para una cadena usada como identificador.
local MAX_STRING_LENGTH = 64

--- Profundidad maxima admitida al recorrer una tabla.
local MAX_TABLE_DEPTH = 4

--- Numero maximo de claves que se recorren en una tabla.
local MAX_TABLE_KEYS = 64

--- Motivos de rechazo. Son estables y legibles: los tests los comparan
--- y el log del servidor los escribe, asi que no se renombran sin motivo.
Guard.Reason = {
	NotATable = "payload_not_a_table",
	WrongType = "wrong_type",
	NotFinite = "not_finite",
	TooLarge = "too_large",
	TooDeep = "too_deep",
	TooManyKeys = "too_many_keys",
	StringTooLong = "string_too_long",
	UnknownField = "unknown_field",
}

--- Indica si un numero es finito (no NaN, no infinito).
---
--- `x ~= x` es la comprobacion de NaN: solo NaN es distinto de si
--- mismo. Un `inf` se filtra comparando contra `math.huge`. Se cubren los
--- dos porque rompen el codigo de forma distinta.
--- @param value any
--- @return boolean
function Guard.IsFiniteNumber(value: any): boolean
	local kind = type(value)

	if kind ~= "number" then
		return false
	end

	if value ~= value then
		return false
	end

	if value == math.huge or value == -math.huge then
		return false
	end

	return true
end

--- Convierte a numero SOLO si es un numero finito y esta dentro de rango.
---
--- Devuelve `nil` en cuanto el valor es `nil`, no numerico, NaN o
--- infinito. Es la unica puerta que deben usar las validaciones que
--- aceptan cifras del cliente: un `tonumber` desnudo devuelve `NaN` sin
--- avisar y el `NaN` se propaga hasta el saldo del jugador.

--- Indica si un valor es una cadena util como identificador.
---
--- Un identificador de item, mundo o codigo: corto, sin codigos de
--- control y no vacio. Se rechaza `""` porque suele ser el valor que un
--- exploit envia para probar si el servidor valida la presencia antes
--- que la forma.
--- @param value any
--- @param maxLength number?
--- @return boolean valid
--- @return string? reason
function Guard.IsIdentifier(value: any, maxLength: number?): (boolean, string?)
	local limit = maxLength or MAX_STRING_LENGTH

	if type(value) ~= "string" then
		return false, Guard.Reason.WrongType
	end

	if #value == 0 then
		return false, Guard.Reason.WrongType
	end

	if #value > limit then
		return false, Guard.Reason.StringTooLong
	end

	-- Codigos de control (0..31 y 127). Se rechazan porque rompen el log
	-- y permiten escribir una linea falsa en un archivo de auditoria.
	for i = 1, #value do
		local byte = string.byte(value, i)

		if byte < 32 or byte == 127 then
			return false, Guard.Reason.WrongType
		end
	end

	return true, nil
end

--- Indica si un valor es una cadena corta de TEXTO LIBRE.
---
--- A diferencia de `IsIdentifier`, aqui si se admiten los espacios: lo
--- usan los motivos de rechazo que ve el jugador. El limite de longitud
--- sigue existiendo porque ese texto va al HUD y a la bitacora.
--- @param value any
--- @param maxLength number?
--- @return boolean valid
--- @return string? reason
function Guard.IsShortText(value: any, maxLength: number?): (boolean, string?)
	local limit = maxLength or MAX_STRING_LENGTH

	if type(value) ~= "string" then
		return false, Guard.Reason.WrongType
	end

	if #value > limit then
		return false, Guard.Reason.StringTooLong
	end

	for i = 1, #value do
		local byte = string.byte(value, i)

		if byte < 32 and byte ~= 9 then
			return false, Guard.Reason.WrongType
		end
	end

	return true, nil
end

--- Recorre una tabla validando que no es ciclica, no es profunda de mas
--- ni tiene demasiadas claves.
---
--- El recorrido lleva un conjunto de "vistas" (`seen`): una tabla que se
--- contiene a si misma NO es un fallo de memoria, es un ataque de
--- recursion infinita. Sin `seen`, un exploit puede colgar el hilo del
--- servidor con una peticion de 200 bytes.
--- @param value any
--- @param maxDepth number?
--- @return boolean valid
--- @return string? reason
function Guard.ValidateTableShape(value: any, maxDepth: number?): (boolean, string?)
	local depthLimit = maxDepth or MAX_TABLE_DEPTH

	if type(value) ~= "table" then
		return false, Guard.Reason.NotATable
	end

	local seen = {}

	local function walk(node: any, depth: number): (boolean, string?)
		if depth > depthLimit then
			return false, Guard.Reason.TooDeep
		end

		local count = 0

		for key, child in pairs(node) do
			count += 1

			if count > MAX_TABLE_KEYS then
				return false, Guard.Reason.TooManyKeys
			end

			-- Solo las claves string o number son esperables. Una clave
			-- que sea una tabla o una funcion indica un payload hecho a
			-- mano que no vino por el camino normal del cliente.
			local keyType = type(key)

			if keyType ~= "string" and keyType ~= "number" then
				return false, Guard.Reason.WrongType
			end

			local childType = type(child)

			if childType == "table" then
				if seen[child] then
					return false, Guard.Reason.TooDeep
				end

				seen[child] = true

				local ok, reason = walk(child, depth + 1)
				seen[child] = nil

				if not ok then
					return false, reason
				end
			elseif childType == "function" or childType == "thread" or childType == "userdata" then
				-- Un cliente no puede enviar una funcion por un RemoteEvent.
				return false, Guard.Reason.WrongType
			end
		end

		return true, nil
	end

	return walk(value, 1)
end

--- Extrae UN campo string del payload, validando su forma.
---
--- Este es el helper que usan las acciones que reciben un `ItemId`, un
--- `WorldId` o un codigo. Hace las TRES comprobaciones que antes se
--- olvidaban por separado: que el payload sea tabla, que la clave exista
--- y que su valor sea un identificador valido.
--- @param payload any
--- @param field string
--- @return boolean valid
--- @return string? value
--- @return string? reason
function Guard.GetIdentifierField(payload: any, field: string): (boolean, string?, string?)
	if type(payload) ~= "table" then
		return false, nil, Guard.Reason.NotATable
	end

	local raw = payload[field]

	if raw == nil then
		return false, nil, Guard.Reason.UnknownField
	end

	local ok, reason = Guard.IsIdentifier(raw)

	if not ok then
		return false, nil, reason
	end

	return true, raw, nil
end

--- Extrae UN campo numerico acotado del payload.
---
--- Igual que `GetIdentifierField`, pero para cifras. `min` y `max` son
--- obligatorios a proposito: un campo numerico sin cota (por ejemplo
--- "cantidad") permitiria `NaN`, negativo o un billon.
--- @param payload any
--- @param field string
--- @param min number
--- @param max number
--- @return boolean valid
--- @return number? value
--- @return string? reason
function Guard.GetBoundedNumberField(payload: any, field: string, min: number, max: number): (boolean, number?, string?)
	if type(payload) ~= "table" then
		return false, nil, Guard.Reason.NotATable
	end

	local raw = payload[field]

	if raw == nil then
		return false, nil, Guard.Reason.UnknownField
	end

	local value = Guard.CoerceNumber(raw, min, max)

	if value == nil then
		-- Se distingue "no es numero" de "esta fuera de rango" porque el
		-- motivo va al log de seguridad y son ataques distintos: un tipo
		-- equivocado indica cliente roto, un rango indica intento.
		if not Guard.IsFiniteNumber(raw) then
			return false, nil, Guard.Reason.NotFinite
		end

		return false, nil, Guard.Reason.TooLarge
	end

	return true, value, nil
end

--- Rejecta cualquier clave del payload que no este en la lista permitida.
---
--- Regla de lista blanca y no de lista negra: si el payload trae
--- `{ ItemId = "Bomb", Admin = true }`, la segunda clave se rechaza aunque
--- nunca se lea. Sin esto, un exploit puede anadir campos a la espera de
--- que alguien los lea sin validarlos.
--- @param payload any
--- @param allowed { [string]: boolean }
--- @return boolean valid
--- @return string? offendingKey
function Guard.RejectUnknownFields(payload: any, allowed: { [string]: boolean }): (boolean, string?)
	if type(payload) ~= "table" then
		return true, nil
	end

	for key in pairs(payload) do
		if type(key) ~= "string" or not allowed[key] then
			return false, tostring(key)
		end
	end

	return true, nil
end

--- Comprueba que la cantidad de argumentos que llego por el remoto es la
--- que el esquema declara.
---
--- Sin esto, `FireServer("Bomb", Extra)` en una accion que espera un
--- argumento llega al handler con uno de mas y, segun como este escrito,
--- puede usar el que sobra. Es un vector clasico.
--- @param received number
--- @param expected number
--- @return boolean valid
function Guard.ValidateArity(received: number, expected: number): boolean
	return received == expected
end
--- @param value any
--- @param min number? cota inferior permitida (por defecto, sin minimo)
--- @param max number? cota superior permitida (por defecto, sin maximo)
--- @return number? number el valor si es valido, o nil
function Guard.CoerceNumber(value: any, min: number?, max: number?): number?
	if not Guard.IsFiniteNumber(value) then
		return nil
	end

	local n = value

	if min ~= nil and n < min then
		return nil
	end

	if max ~= nil and n > max then
		return nil
	end

	return n
end

return Guard