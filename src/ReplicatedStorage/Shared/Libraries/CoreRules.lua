--!strict
--[[
	CoreRules
	Logica PURA del Keshusy Core: maquina de estados, carga y limites.

	Por que existe (mismo motivo que CombatMath):
	Las reglas que deciden si un fragmento se acepta y que estado
	provoca son FORMULAS. Si viven dentro de CoreService no se pueden
	probar: `luau.exe` no tiene Workspace ni Players. Este modulo las
	aisla para que la suite las ejecute de verdad.

	Regla: aqui no se toca ningun objeto del juego. Solo numeros que
	entran y numeros que salen, mas una tabla de estado pequena. El
	cliente NUNCA decide nada: esto solo responde a lo que le pregunta
	el servidor.
]]

local CoreRules = {}

CoreRules.State = {
	Inactive = "Inactive",
	Activating = "Activating",
	Active = "Active",
	Overloaded = "Overloaded",
	Event = "Event",
}

--- Estados en los que el nucleo ACEPTA un fragmento.
--- `Activating` no aparece: durante la secuencia el nucleo esta
--- bloqueado, y `Overloaded` tampoco porque se esta drenando.
CoreRules.AcceptsFragments = {
	[CoreRules.State.Inactive] = true,
	[CoreRules.State.Active] = true,
	[CoreRules.State.Event] = true,
}

--- Estado inicial de un nucleo recien creado.
--- @return table state
function CoreRules.NewState()
	return {
		State = CoreRules.State.Inactive,
		Charge = 0,
		-- Fragmentos aportados por jugador en esta ronda de carga.
		FragmentsByPlayer = {},
		-- Ultimo instante en que cada jugador aporto un fragmento.
		LastFragmentAtByPlayer = {},
		-- Instante en que empieza y termina la secuencia de activacion.
		ActivationStartedAt = nil,
		ActivationEndsAt = nil,
		-- Instante en que termina el evento, si lo hay.
		EventEndsAt = nil,
		-- Activaciones completas. Es lo que consume el desbloqueo.
		ActivationCount = 0,
	}
end

--- Un numero utilizable: ni NaN ni infinito.
--- Se repite aqui (y no se usa CombatMath) porque este modulo no debe
--- depender de otro: asi puede probarse aislado.
--- @param value any
--- @return boolean
local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--- Normaliza la carga a un rango utilizable.
---
--- Una carga corrupta (NaN, infinito, negativa) NO se propaga: un NaN
--- en la barra rompe la UI y puede dejar el nucleo bloqueado para
--- siempre. Aqui se sella.
---
--- El infinito POSITIVO se recorta al maximo y no a cero: es una carga
--- "demasiado grande", no una carga "inexistente". Distinguirlo importa:
--- con un max de 100, tratar `+inf` como 0 borraria una barra llena y
--- el nucleo volveria a Inactive cuando en realidad esta sobrecargado.
--- El infinito NEGATIVO y el NaN si se sellan a 0, porque no describen
--- una carga grande sino una corrupta.
--- @param charge any
--- @param maxCharge number
--- @return number charge
function CoreRules.ClampCharge(charge: any, maxCharge: number): number
	if type(charge) ~= "number" or charge ~= charge then
		-- NaN: no es comparable con nada. Se sella a 0.
		return 0
	end

	if charge == math.huge then
		return maxCharge
	end

	if charge == -math.huge then
		return 0
	end

	if charge < 0 then
		return 0
	end

	if charge > maxCharge then
		return maxCharge
	end

	return charge
end

--- Indica si el nucleo admite un fragmento en su estado actual.
--- @param state string
--- @return boolean
function CoreRules.CanAcceptFragment(state: string): boolean
	return CoreRules.AcceptsFragments[state] == true
end

--- Copia profunda de las tablas del estado.
--- Se usa para que un rechazo NO deje el estado real a medias.
--- @param state table
--- @return table
local function copyState(state: any): table
	local nextState = {
		State = state.State,
		Charge = state.Charge,
		FragmentsByPlayer = {},
		LastFragmentAtByPlayer = {},
		ActivationStartedAt = state.ActivationStartedAt,
		ActivationEndsAt = state.ActivationEndsAt,
		EventEndsAt = state.EventEndsAt,
		ActivationCount = state.ActivationCount,
	}

	for id, amount in pairs(state.FragmentsByPlayer or {}) do
		nextState.FragmentsByPlayer[id] = amount
	end

	for id, at in pairs(state.LastFragmentAtByPlayer or {}) do
		nextState.LastFragmentAtByPlayer[id] = at
	end

	return nextState
end

CoreRules._copyState = copyState
--- Resultado de intentar aportar un fragmento.
---
--- Devuelve el estado MUTADO y el motivo del rechazo, nunca "true" a
--- medias: el servidor necesita saber por que se rechazo para poder
--- responder al cliente y registrarlo.
--- @param state table estado de CoreRules.NewState()
--- @param playerId number
--- @param options table { maxCharge, chargePerFragment, fragmentsPerPlayer, fragmentCooldown, now }
--- @return boolean accepted
--- @return string? reason
--- @return table? nextState el estado NUEVO, o nil si se rechazo
function CoreRules.TryAddFragment(state: any, playerId: number, options: any): (boolean, string?, table?)
	local maxCharge = options.maxCharge
	local chargePerFragment = options.chargePerFragment
	local fragmentsPerPlayer = options.fragmentsPerPlayer
	local fragmentCooldown = options.fragmentCooldown or 0
	local now = options.now or 0

	if type(state) ~= "table" or type(playerId) ~= "number" then
		return false, "peticion invalida", nil
	end

	if not isFinite(maxCharge) or maxCharge <= 0 then
		return false, "configuracion invalida", nil
	end

	if not isFinite(chargePerFragment) or chargePerFragment <= 0 then
		return false, "configuracion invalida", nil
	end

	-- 1. Estado del nucleo. Es la primera comprobacion porque es la que
	--    explica la mayoria de los rechazos en juego.
	if not CoreRules.CanAcceptFragment(state.State) then
		return false, ("nucleo en estado %s"):format(tostring(state.State)), nil
	end

	-- 2. Limite por jugador. Sin esto, un jugador con latencia favorable
	--    llenaria la barra solo, sin cooperacion.
	local given = state.FragmentsByPlayer[playerId] or 0
	if given >= fragmentsPerPlayer then
		return false, "limite de fragmentos alcanzado", nil
	end

	-- 3. Recarga por jugador. Evita el envio masivo de fragmentos.
	local lastAt = state.LastFragmentAtByPlayer and state.LastFragmentAtByPlayer[playerId]
	if lastAt and (now - lastAt) < fragmentCooldown then
		return false, "demasiado rapido", nil
	end

	-- Se trabaja sobre una COPIA: si algo falla mas abajo, el estado
	-- real no debe haber cambiado. Mutar aqui y devolver nil seria un
	-- fallo silencioso de estado.
	local nextState = copyState(state)

	local newCharge = CoreRules.ClampCharge(nextState.Charge + chargePerFragment, maxCharge)
	nextState.Charge = newCharge
	nextState.FragmentsByPlayer[playerId] = given + 1
	nextState.LastFragmentAtByPlayer[playerId] = now

	-- 4. Alcanzar el maximo dispara la activacion. Es la UNICA transicion
	--    que un fragmento puede provocar.
	if newCharge >= maxCharge then
		nextState.State = CoreRules.State.Activating
		nextState.ActivationStartedAt = now
		nextState.ActivationEndsAt = now + (options.activationDuration or 0)
	end

	return true, nil, nextState
end
--- Avanza la maquina de estados con el reloj.
---
--- Es idempotente dentro de cada ventana: llamarla dos veces con el
--- mismo instante no completa dos activaciones.
--- @param state table
--- @param now number
--- @param options table { maxCharge, drainPerSecond, step }
--- @return table nextState
function CoreRules.Advance(state: any, now: number, options: any): table
	local maxCharge = options.maxCharge
	local step = options.step or 0
	local nextState = copyState(state)
	nextState.Charge = CoreRules.ClampCharge(nextState.Charge, maxCharge)

	if nextState.State == CoreRules.State.Activating then
		-- Solo se completa si la ventana de activacion YA TERMINO. El
		-- `<=` importa: el instante exacto de cierre completa.
		if nextState.ActivationEndsAt and now >= nextState.ActivationEndsAt then
			nextState.State = CoreRules.State.Active
			nextState.ActivationCount = (state.ActivationCount or 0) + 1
			nextState.EventEndsAt = now + (options.eventDuration or 0)
		end
	elseif nextState.State == CoreRules.State.Overloaded then
		-- La sobrecarga se drena sola. Al bajar del maximo el nucleo
		-- vuelve a ser inerte, no "activo".
		local drained = CoreRules.ClampCharge(
			nextState.Charge - (options.drainPerSecond or 0) * step,
			maxCharge
		)
		nextState.Charge = drained
		if drained < maxCharge then
			nextState.State = CoreRules.State.Inactive
		end
	elseif nextState.State == CoreRules.State.Event then
		if nextState.EventEndsAt and now >= nextState.EventEndsAt then
			nextState.State = CoreRules.State.Active
			nextState.EventEndsAt = nil
		end
	elseif nextState.State == CoreRules.State.Active then
		-- El nucleo activo se descarga poco a poco para poder volver a
		-- cargarse. Sin esto se quedaria pegado en "activo" para siempre.
		local drained = CoreRules.ClampCharge(
			nextState.Charge - (options.passiveDrainPerSecond or 0) * step,
			maxCharge
		)
		nextState.Charge = drained
		if drained < maxCharge then
			nextState.State = CoreRules.State.Inactive
		end
	end

	return nextState
end

--- Pasa el nucleo a sobrecarga. Se usa cuando la carga llega al maximo
--- por una via que no sea un fragmento, o cuando se pasa de la maxima.
--- @param state table
--- @param charge any
--- @param maxCharge number
--- @return table nextState
function CoreRules.Overload(state: any, charge: any, maxCharge: number): table
	local nextState = copyState(state)
	nextState.Charge = CoreRules.ClampCharge(charge, maxCharge)

	if nextState.Charge >= maxCharge then
		nextState.State = CoreRules.State.Overloaded
	end

	return nextState
end

--- Fraccion de carga normalizada, para pintar la barra.
--- @param charge any
--- @param maxCharge number
--- @return number fraction en [0, 1]
function CoreRules.ChargeFraction(charge: any, maxCharge: number): number
	if not isFinite(maxCharge) or maxCharge <= 0 then
		return 0
	end

	return CoreRules.ClampCharge(charge, maxCharge) / maxCharge
end

return CoreRules
