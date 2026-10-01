--!strict
--[[
	StateMachine
	Maquina de estados reutilizable y testeable.

	Se usa para los estados del servidor, de la ronda y del jugador.
	Centraliza una sola garantia importante: una transicion debe ser
	declarada de forma explicita. No se permite cambiar de estado a
	cualquier valor, lo que evita estados imposibles y bucles.

	No depende de servicios de Roblox.
]]

local StateMachine = {}
StateMachine.__index = StateMachine

export type TransitionHook = (from: string, to: string) -> ()

export type StateMachineOptions = {
	-- Nombre del estado inicial.
	initial: string,
	-- Estados validos: tabla estado -> estado siguiente permitido.
	-- "*" permite cualquier estado (usado solo si es necesario).
	transitions: { [string]: { string } },
	-- Estados que terminan la maquina (no admiten salida).
	terminal: { string }?,
}

--- Crea una maquina de estados.
--- @param options StateMachineOptions
--- @return table
function StateMachine.new(options: StateMachineOptions)
	local initial = options.initial
	local transitions = options.transitions

	assert(type(initial) == "string" and initial ~= "", "StateMachine: initial requerido")
	assert(type(transitions) == "table", "StateMachine: transitions requeridos")
	assert(transitions[initial] ~= nil, ("StateMachine: estado inicial '%s' no declarado"):format(initial))

	local terminal = {}
	for _, state in options.terminal or {} do
		terminal[state] = true
	end

	local self = setmetatable({
		_current = initial,
		_transitions = transitions,
		_terminal = terminal,
		_hooks = {},
		_history = { initial },
		_isRunning = true,
	}, StateMachine)

	return self
end

--- Estado actual.
function StateMachine:Get(): string
	return self._current
end

--- Historial de estados visitados (el primero es el inicial).
function StateMachine:GetHistory(): { string }
	return table.clone(self._history)
end

--- Indica si un estado es alcanzable desde el actual.
--- @param target string
--- @return boolean
function StateMachine:CanTransition(target: string): boolean
	if not self._isRunning then
		return false
	end
	if self._terminal[self._current] then
		return false
	end

	local allowed = self._transitions[self._current]
	if not allowed then
		return false
	end

	for _, state in allowed do
		if state == target or state == "*" then
			return true
		end
	end

	return false
end

--- Ejecuta una transicion. Devuelve false si no esta permitida.
--- @param target string
--- @return boolean success
function StateMachine:Transition(target: string): boolean
	if not self:CanTransition(target) then
		return false
	end

	local previous = self._current
	self._current = target
	table.insert(self._history, target)

	for _, hook in self._hooks do
		hook(previous, target)
	end

	return true
end

--- Registra un hook de transicion (no es cleanup: vive toda la maquina).
--- @param hook TransitionHook
--- @return any handle funcion para desregistrar
function StateMachine:OnTransition(hook: TransitionHook): () -> ()
	table.insert(self._hooks, hook)

	return function()
		for index = #self._hooks, 1, -1 do
			if self._hooks[index] == hook then
				table.remove(self._hooks, index)
				break
			end
		end
	end
end

--- Detiene la maquina: ya no admite transiciones.
function StateMachine:Stop()
	self._isRunning = false
end

--- Indica si la maquina sigue activa.
function StateMachine:IsRunning(): boolean
	return self._isRunning
end

--- Reinicia la maquina al estado inicial vaciando el historial.
function StateMachine:Reset(initial: string?)
	local target = initial or self._history[1]
	if not self._transitions[target] then
		error(("StateMachine: estado de reinicio '%s' no declarado"):format(tostring(target)), 0)
	end

	self._current = target
	self._history = { target }
end

return StateMachine