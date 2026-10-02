--!strict
--[[
	TestDriverLogic
	Instrucciones del reproductor de pruebas del cliente. LOGICA PURA.

	Por que vive aqui y no en el LocalScript
	-----------------------------------------
	El reproductor decide QUE instruccion corresponde y si se puede
	ejecutar. Esa decision es logica pura y por tanto se prueba de verdad
	con `luau.exe`, sin Studio, sin motor y sin jugador.

	Lo que este modulo NO hace (deliberadamente)
	---------------------------------------------
	No conoce controllers, ni remotos, ni servicios. Solo decide la
	accion y su validez. La EJECUCION ocurre en el cliente, sobre los
	controllers reales, que a su vez disparan los remotos reales.

	Por eso la prueba que pasa por aqui sigue siendo la prueba del
	jugador: este modulo no puede saltarse ni el InputController, ni el
	Remote, ni la validacion del servidor, ni el RateLimiter, ni el
	servicio. Como no tiene ninguna referencia a ellos, no hay forma de
	que los esquive.
]]

local Logic = {}

--- Instrucciones que el servidor puede pedir al cliente.
--
-- Se declaran como texto porque llegan por un atributo, que solo admite
-- strings y numeros. Cada nombre corresponde a UNA intencion de jugador.
Logic.Actions = {
	PlaceBomb = "PlaceBomb",
	EnterPortal = "EnterPortal",
	RequestState = "RequestState",
}

Logic.ActionByName = {
	PlaceBomb = Logic.Actions.PlaceBomb,
	EnterPortal = Logic.Actions.EnterPortal,
	RequestState = Logic.Actions.RequestState,
}

--- Instrucciones que el reproductor sabe ejecutar.
--- @return { string }
function Logic.SupportedActions(): { string }
	local names = {}

	for name in pairs(Logic.ActionByName) do
		table.insert(names, name)
	end

	table.sort(names)
	return names
end

--- Traduce el texto recibido a una instruccion.
--- @param raw any
--- @return string? action
--- @return string? reason motivo del rechazo
function Logic.Parse(raw: any): (string?, string?)
	if type(raw) ~= "string" then
		return nil, "la instruccion debe ser texto"
	end

	local action = Logic.ActionByName[raw]

	if not action then
		return nil, ("instruccion desconocida: %s"):format(raw)
	end

	return action, nil
end

--- Indica si una instruccion se puede ejecutar ahora.
---
--- Rechaza las de tipo espam a proposito: una instruccion repetida en
--- bucle es exactamente lo que un jugador real no podria hacer por el
--- cooldown del servidor, y probarlo asi no probaria nada.
--- @param action string
--- @param lastRunAt number? instante de la ejecucion anterior
--- @param now number instante actual
--- @param minIntervalSeconds number intervalo minimo entre ejecuciones
--- @return boolean allowed
--- @return string? reason
function Logic.CanRun(action: string, lastRunAt: number?, now: number, minIntervalSeconds: number): (boolean, string?)
	if not Logic.ActionByName[action] then
		return false, ("instruccion no soportada: %s"):format(tostring(action))
	end

	if minIntervalSeconds <= 0 then
		return true, nil
	end

	if lastRunAt and now < lastRunAt then
		return false, "el reloj retrocedio"
	end

	if lastRunAt and (now - lastRunAt) < minIntervalSeconds then
		return false, ("espera %.2fs entre ejecuciones"):format(minIntervalSeconds)
	end

	return true, nil
end

--- Texto de una instruccion para enviar por atributo.
--- @param action string
--- @param worldId string? destino del portal
--- @return string
function Logic.Encode(action: string, worldId: string?): string
	if worldId and worldId ~= "" then
		return ("%s|%s"):format(action, worldId)
	end

	return action
end

--- Lee una instruccion codificada.
--- @param encoded any
--- @return string? action
--- @return string? worldId
--- @return string? reason
function Logic.Decode(encoded: any): (string?, string?, string?)
	if type(encoded) ~= "string" then
		return nil, nil, "la instruccion debe ser texto"
	end

	local action, worldId = encoded:match("^([^|]+)|(.+)$")

	if not action then
		action = encoded
	end

	-- SUFIJO DE SECUENCIA.
	--
	-- El servidor anade "#<n>" al final del valor para que el atributo
	-- SIEMPRE cambie de valor. Sin esto, repetir la misma accion no dispara
	-- `GetAttributeChangedSignal` y el cliente se queda esperando: la prueba
	-- parece un fallo del cliente cuando en realidad nadie ha recibido nada.
	--
	-- Se recorta en el cliente, que es quien lo recibe. Antes se recortaba en
	-- la parte que lo envia, y el fallo era peor: `EnterPortal|Forest|2` se
	-- partia por la barra vertical en un unico destino "Forest|2", con lo que
	-- el portal parecia no existir y el servidor rechazaba una entrada valida.
	if action then
		action = action:gsub("#%d+$", "")
	end

	if worldId then
		worldId = worldId:gsub("#%d+$", "")
	end

	local parsed, reason = Logic.Parse(action)

	if not parsed then
		return nil, nil, reason
	end

	return parsed, worldId, nil
end

return Logic