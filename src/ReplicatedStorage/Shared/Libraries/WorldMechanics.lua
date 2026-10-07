--!strict
--[[
	WorldMechanics
	MECANICAS EXPANDIDAS POR MUNDO (FASE 4).

	POR QUE EXISTE
	--------------
	La FASE 3 anadio un peligro por mundo (HazardRules): emboscada, arena
	movediza, racha de viento, lava y laser. Funciona, pero un solo peligro
	por mundo deja cada mundo con una sola decision: "entrar aqui cuesta".

	FASE 4 amplia la tabla: cada mundo tiene ahora un CONJUNTO de mecanicas
	que se cruzan entre si para darle identidad jugable. La arquitectura es
	UNICA: `WorldMechanics` define el catalogo y la aritmetica PURA (estados,
	transiciones por reloj, danos, cooldowns, validacion de posicion); el
	servicio (`WorldMechanicsService`) aporta el hilo, las partes y la
	lectura de posiciones.

	QUE VIVE AQUI Y QUE NO
	----------------------
	Aqui vive el catalogo, las maquinas de fase y toda la aritmetica: es
	puro y se prueba con `luau.exe`. El servicio aporta el motor.

	LA REGLA DE AUTORIDAD
	---------------------
	Todo dano pasa por `CombatService.ApplyDamage`, la unica autoridad de
	dano. Todo avance de actividad pasa por `ActivityService.RecordMetric`.
	Este modulo NO decide recompensas ni estado de jugador: define QUE puede
	suceder y calcula CUANDO, pero no QUIEN paga ni QUIEN recibe.

	MULTIPLAYER-SAFE
	-----------------
	El estado del servidor esta ESCOPED a (mundo, zona, evento). No hay
	estado global por jugador: cada jugador recibe la misma fase de un
	evento temporal, y los cooldowns son por evento, no por jugador. Esto
	evita que un jugador vea una fase distinta a otro en el mismo servidor.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- TIPOS DE MECANICA
-- ---------------------------------------------------------------------------

Rules.MechanicKind = {
	-- Zona de descubrimiento: punto interactivo para actividades de tipo
	-- Discovery. El jugador activa un ProximityPrompt y avanza la actividad.
	HiddenZone = "HiddenZone",

	-- Mecanismo natural: activa un objeto del mapa (raices, rocas, totems).
	-- Usa la actividad de tipo Mechanic.
	NaturalMechanism = "NaturalMechanism",

	-- Tesoro enterrado: punto de excavacion. La actividad de tipo
	-- Collection avanza al estar cerca y ejecutar la interaccion.
	BuriedTreasure = "BuriedTreasure",

	-- Terminal de red: maquina de estados OFFLINE -> ACCESS -> ACTIVE -> COMPLETE.
	Terminal = "Terminal",

	-- Puerta de seguridad: abierta por un terminal, interruptor o actividad.
	SecurityDoor = "SecurityDoor",

	-- Plataforma de hielo frailible: Stable -> Cracked -> Broken.
	FragilePlatform = "FragilePlatform",

	-- Evento temporal con fases (tormenta, erupcion, etc).
	TemporalEvent = "TemporalEvent",

	-- Objeto coleccionable fisico por el mapa.
	Collectible = "Collectible",
}

-- ---------------------------------------------------------------------------
-- ESTADOS DE EVENTOS TEMPORALES
-- ---------------------------------------------------------------------------

Rules.TemporalPhase = {
	-- Estado base: nada esta pasando.
	Calm = "Calm",
	-- Anuncio: el evento viene. Telegrafo visual/auditivo.
	Warning = "Warning",
	-- El evento esta activo: danos, reduccion de visibilidad, etc.
	Active = "Active",
	-- Se esta recuperando: el evento termino, hay margen de safety.
	Recovery = "Recovery",
}

-- ---------------------------------------------------------------------------
-- ESTADOS DE TERMINALES
-- ---------------------------------------------------------------------------

Rules.TerminalState = {
	-- Terminal inactiva: necesita un gesto para activarse.
	Offline = "Offline",
	-- El jugador esta interactuando: acceso en curso.
	Accessing = "Accessing",
	-- Terminal activa: produce su efecto (abre puertas, desactiva lasers).
	Active = "Active",
	-- Terminal ya fue usada: no se reusan sin reset.
	Complete = "Complete",
}

-- ---------------------------------------------------------------------------
-- ESTADOS DE PLATAFORMAS FRAILES
-- ---------------------------------------------------------------------------

Rules.FragileState = {
	-- Plataforma estable: soporta peso.
	Stable = "Stable",
	-- Deformed: se ha activado, hay que salir.
	Cracked = "Cracked",
	-- Rompida: desaparece.
	Broken = "Broken",
}

-- ---------------------------------------------------------------------------
-- LIMITES Y RITMO
-- ---------------------------------------------------------------------------

--- Segundos de la fase de advertencia antes del evento activo.
Rules.WarningDuration = 5

--- Segundos de la fase activa del evento.
Rules.ActiveDuration = 15

--- Segundos de recovery despues del evento.
Rules.RecoveryDuration = 8

--- Cooldown entre activaciones de un mismo evento temporal (segundos).
---
--- No es un numero magico: un evento que se repita sin parar no es un
--- desafio, es ruido. 120 s es el minimo que deja tiempo al jugador a
--- explorar, morir, reaparecer y volver.
Rules.EventCooldown = 120

--- Duracion de la fase de acceso a un terminal (segundos).
---
--- El jugador debe estar detenido interactuando: demasiado corto y no
--- termina de pulsar; demasiado largo y frustra.
Rules.TerminalAccessDuration = 2.5

--- Tiempo entre `Cracked` y `Broken` (segundos).
---
--- La plataforma se deforma y el jugador tiene este margen REAL para
--- reaccionar y salir. No se puede saltar: la mecanica exige decision.
Rules.DefaultCrackWindow = 1.0

--- Distancia maxima de interaccion (studs). El servidor la mide.
Rules.InteractRange = 18

--- ---------------------------------------------------------------------------
--- Velocidad base del jugador (igual que HazardRules).
--- Se usa para aplicar modificadores de movimiento de las mecanicas.
--- ---------------------------------------------------------------------------
Rules.DefaultWalkSpeed = 16

-- ---------------------------------------------------------------------------
-- CONFIGURACION POR MUNDO
-- ---------------------------------------------------------------------------

Rules.MechanicsByWorld = {
	Forest = {
		-- Rastros: tracks que dejan los jugadores, usados por IA para perseguir.
		-- No es un peligro de dano: es una capa de informacion que el servicio
		-- de IA consume. El `TrailDuration` define cuanto tiempo persiste.
		Tracking = {
			TrailDuration = 30,
			TrailInterval = 2,
		},

		-- Mecanismos naturales del bosque: totems, rocas vivas, raices.
		NaturalMechanisms = {
			{ Kind = Rules.MechanicKind.HiddenZone, Count = 2 },
			{ Kind = Rules.MechanicKind.NaturalMechanism, Count = 3 },
		},

		-- No hay eventos temporales propios de Forest: la emboscada ya
		-- provee sorpresa. La ausencia tambien es una decision de balance.
		TemporalEvents = nil,
	},

	Desert = {
		-- Tormentas de arena: evento temporal con fases.
		TemporalEvents = {
			{
				Kind = "Sandstorm",
				WarningDuration = Rules.WarningDuration,
				ActiveDuration = 20,
				RecoveryDuration = Rules.RecoveryDuration,
				Cooldown = Rules.EventCooldown,
				-- Reducion de visibilidad durante la tormenta (fraccion 0..1).
				Visibility = 0.35,
			},
		},

		-- Tesoros enterrados: puntos de excavacion.
		BuriedTreasures = {
			Count = 4,
			-- Probabilidad de que un punto tenga un tesoro (0..1).
			Probability = 0.8,
		},

		-- Oasis: puntos seguros que anulan efectos negativos.
		Oases = {
			Count = 2,
			Radius = 14,
		},
	},

	Ice = {
		-- Hielo deslizante: modificador de friccion.
		SlipperyIce = {
			SpeedMultiplier = 1.3,
			ControlLoss = 0.4,
		},

		-- Plataformas de hielo frailible.
		FragilePlatforms = {
			Count = 3,
			CrackWindow = Rules.FragileCrackWindow,
		},

		-- Tormenta de hielo: evento temporal con fases.
		TemporalEvents = {
			{
				Kind = "Blizzard",
				WarningDuration = Rules.WarningDuration,
				ActiveDuration = 18,
				RecoveryDuration = Rules.RecoveryDuration,
				Cooldown = Rules.EventCooldown,
				Visibility = 0.25,
			},
		},
	},

	Volcano = {
		-- Erupcion: evento temporal con fases.
		TemporalEvents = {
			{
				Kind = "Eruption",
				WarningDuration = Rules.WarningDuration,
				ActiveDuration = 22,
				RecoveryDuration = Rules.RecoveryDuration,
				Cooldown = Rules.EventCooldown,
				-- Danos por segundo durante la fase activa (entra por CombatService).
				DamagePerSecond = 8,
			},
		},

		-- Meteoros: objetivos anunciados que caen de la sky.
		MeteorShower = {
			Interval = 6,
			Damage = 35,
			TelegraphTime = 1.0,
		},

		-- Rutas cambiantes: paths que se abren/cierran con la erupcion.
		DynamicRoutes = {
			Count = 2,
			MinOpenDuration = 10,
		},
	},

	Cyber = {
		-- Terminales: maquina de estados OFFLINE -> ACCESS -> ACTIVE -> COMPLETE.
		Terminals = {
			Count = 3,
			AccessDuration = Rules.TerminalAccessDuration,
		},

		-- Puertas de seguridad controladas por terminales.
		SecurityDoors = {
			Count = 2,
		},

		-- Lasers de seguridad con patron de encendido.
		SecurityLasers = {
			Count = 4,
			OnTime = 2.5,
			OffTime = 3.5,
			DamagePerPulse = 12,
		},

		-- Rutas dinamicas controladas por terminales.
		DynamicRoutes = {
			Count = 2,
		},
	},
}

-- ---------------------------------------------------------------------------
-- CONSULTAS
-- ---------------------------------------------------------------------------

--- Mecanicas de un mundo, o nil si no existe.
--- @param worldId any
--- @return any?
function Rules.ForWorld(worldId: any): any?
	if type(worldId) ~= "string" then
		return nil
	end

	return Rules.MechanicsByWorld[worldId]
end

--- Mundos con mecanicas, en orden estable.
--- @return { string }
function Rules.GetWorldIds(): { string }
	local out = {}

	for worldId in pairs(Rules.MechanicsByWorld) do
		table.insert(out, worldId)
	end

	table.sort(out)
	return out
end

--- Eventos temporales de un mundo.
--- @param worldId string
--- @return { any }|nil
function Rules.GetTemporalEvents(worldId: string): { any } | nil
	local mechanics = Rules.MechanicsByWorld[worldId]

	if not mechanics then
		return nil
	end

	return mechanics.TemporalEvents
end

-- ---------------------------------------------------------------------------
-- MAQUINA DE FASES TEMPORAL
-- ---------------------------------------------------------------------------

--- Fase activa de un evento temporal en este instante.
---
--- La fase se deriva del reloj y no de un contador del servicio: dos servidores
--- con el mismo reloj ven la misma fase, y un evento nunca se queda en una
--- fase por un tick perdido.
--- @param eventDef any definicion del evento (TiempoWarning/Duration/Recovery/Cooldown)
--- @param cycleStart number cuando empezo el ciclo actual
--- @param now number tiempo actual
--- @return string phase (`TemporalPhase.*`)
function Rules.TemporalPhaseAt(eventDef: any, cycleStart: number, now: number): string
	if type(eventDef) ~= "table" then
		return Rules.TemporalPhase.Calm
	end

	local elapsed = tonumber(now) - tonumber(cycleStart)

	if elapsed < 0 then
		return Rules.TemporalPhase.Calm
	end

	local warning = tonumber(eventDef.WarningDuration) or Rules.WarningDuration
	local active = tonumber(eventDef.ActiveDuration) or Rules.ActiveDuration
	local recovery = tonumber(eventDef.RecoveryDuration) or Rules.RecoveryDuration
	local cooldown = tonumber(eventDef.Cooldown) or Rules.EventCooldown

	local totalCycle = warning + active + recovery + cooldown

	if elapsed >= totalCycle then
		return Rules.TemporalPhase.Calm
	end

	if elapsed < warning then
		return Rules.TemporalPhase.Warning
	end

	elapsed -= warning

	if elapsed < active then
		return Rules.TemporalPhase.Active
	end

	elapsed -= active

	if elapsed < recovery then
		return Rules.TemporalPhase.Recovery
	end

	return Rules.TemporalPhase.Calm
end

--- Danos que aplica un evento temporal en este paso del tick.
---
--- La lava y la tormenta danan solo en fase activa. El dano se prorratea
--- al tick para que sea independiente del intervalo del servicio.
--- @param eventDef any
--- @param cycleStart number
--- @param now number
--- @param tickSeconds number
--- @return number dano del paso (0 = este paso no dania)
function Rules.TemporalDamagePerTick(
	eventDef: any,
	cycleStart: number,
	now: number,
	tickSeconds: number
): number
	if type(eventDef) ~= "table" then
		return 0
	end

	local phase = Rules.TemporalPhaseAt(eventDef, cycleStart, now)

	if phase ~= Rules.TemporalPhase.Active then
		return 0
	end

	local dps = tonumber(eventDef.DamagePerSecond) or 0
	local dt = tonumber(tickSeconds) or 0.5

	return dps * dt
end

--- Indica si un evento temporal esta en fase activa en este instante.
--- @param eventDef any
--- @param cycleStart number
--- @param now number
--- @return boolean
function Rules.IsEventActive(eventDef: any, cycleStart: number, now: number): boolean
	return Rules.TemporalPhaseAt(eventDef, cycleStart, now) == Rules.TemporalPhase.Active
end

--- Visibilidad durante el evento (1 = normal, 0 = ciego).
---
--- La noche tambien reduce visibilidad; el evento la multiplica.
--- @param eventDef any
--- @param cycleStart number
--- @param now number
--- @return number factor 0..1
function Rules.VisibilityFactor(eventDef: any, cycleStart: number, now: number): number
	if type(eventDef) ~= "table" then
		return 1
	end

	if Rules.IsEventActive(eventDef, cycleStart, now) then
		local vis = tonumber(eventDef.Visibility) or 0.5
		return math.clamp(vis, 0, 1)
	end

	return 1
end

-- ---------------------------------------------------------------------------
-- MAQUINA DE ESTADOS DE TERMINAL
-- ---------------------------------------------------------------------------

--- Transicion valida de estado de terminal.
---
--- Las transiciones son EXPLICITAS: no se puede pasar de Offline a Active
--- sin pasar por Accessing. Esto evita que un exploit salte directamente
--- al estado final.
--- @param from string estado actual
--- @param to string estado objetivo
--- @return boolean
function Rules.CanTerminalTransition(from: string, to: string): boolean
	if from == Rules.TerminalState.Offline then
		return to == Rules.TerminalState.Accessing
	end

	if from == Rules.TerminalState.Accessing then
		return to == Rules.TerminalState.Active or to == Rules.TerminalState.Offline
	end

	if from == Rules.TerminalState.Active then
		return to == Rules.TerminalState.Complete or to == Rules.TerminalState.Offline
	end

	if from == Rules.TerminalState.Complete then
		return to == Rules.TerminalState.Offline
	end

	return false
end

--- Tiempo que debe mantenerse el jugador en `Accessing` para pasar a `Active`.
--- @param eventDef any
--- @return number
function Rules.TerminalAccessTime(eventDef: any): number
	if type(eventDef) ~= "table" then
		return Rules.TerminalAccessDuration
	end

	return tonumber(eventDef.AccessDuration) or Rules.TerminalAccessDuration
end

-- ---------------------------------------------------------------------------
-- MAQUINA DE ESTADOS DE PLATAFORMA FRAIL
-- ---------------------------------------------------------------------------

--- Transicion valida de estado de plataforma frail.
---
--- El orden es INVERSAMENTE PROGRESIVO: Stable -> Cracked -> Broken.
--- No se puede revertir una plataforma rota a menos que el evento lo reinicie.
--- @param from string
--- @param to string
--- @return boolean
function Rules.CanFragileTransition(from: string, to: string): boolean
	if from == Rules.FragileState.Stable then
		return to == Rules.FragileState.Cracked
	end

	if from == Rules.FragileState.Cracked then
		return to == Rules.FragileState.Broken
	end

	return false
end

--- Tiempo que una plataforma tarda en pasar de Cracked a Broken.
--- @param eventDef any
--- @return number
function Rules.FragileCrackWindow(eventDef: any): number
	if type(eventDef) ~= "table" then
		return Rules.DefaultCrackWindow
	end

	return tonumber(eventDef.CrackWindow) or Rules.DefaultCrackWindow
end

-- ---------------------------------------------------------------------------
-- ARITMETICA DE MOVIMIENTO
-- ---------------------------------------------------------------------------

--- Velocidad de caminar con un multiplicador aplicado.
---
--- El multiplicador viene del catalogo del mundo (p. ej. hielo deslizante).
--- Se acota a un minimo para que no se llegue a velocidad cero (inmovilizacion).
--- @param speedMultiplier number
--- @return number
function Rules.ModifiedWalkSpeed(speedMultiplier: number): number
	local mult = tonumber(speedMultiplier) or 1

	if mult ~= mult or mult == math.huge or mult == -math.huge then
		return Rules.DefaultWalkSpeed
	end

	return math.max(1, math.floor(Rules.DefaultWalkSpeed * mult))
end

-- ---------------------------------------------------------------------------
-- VALIDACION DE INTERACCION
-- ---------------------------------------------------------------------------

--- Distancia al cuadrado entre una posicion y un punto (sin raiz).
---
--- Usa campos `.X` / `.Z` para que funcione tanto con `Vector3` del motor
--- como con una tabla de prueba. Medir XZ (plano horizontal) es lo que
--- interesa para interacciones de terreno.
--- @param a { X: number, Z: number }
--- @param b { X: number, Z: number }
--- @return number
function Rules.DistanceSqXZ(a: any, b: any): number
	if type(a) ~= "table" or type(b) ~= "table" then
		return math.huge
	end

	local dx = (tonumber(a.X) or 0) - (tonumber(b.X) or 0)
	local dz = (tonumber(a.Z) or 0) - (tonumber(b.Z) or 0)

	return dx * dx + dz * dz
end

--- Indica si una posicion esta dentro del rango de interaccion de un punto.
---
--- El servidor mide: el cliente no manda distancia.
--- @param playerPos { X: number, Z: number }
--- @param pointPos { X: number, Z: number }
--- @param range number?
--- @return boolean
function Rules.IsInRange(playerPos: any, pointPos: any, range: number?): boolean
	local r = tonumber(range) or Rules.InteractRange

	if r <= 0 then
		return false
	end

	local distSq = Rules.DistanceSqXZ(playerPos, pointPos)

	return distSq <= r * r
end

-- ---------------------------------------------------------------------------
-- VALIDACION DE CONFIGURACION
-- ---------------------------------------------------------------------------

--- Comprueba que el catalogo de mecanicas es coherente.
---
--- Se ejecuta al ARRANCAR y en tests: cada mundo debe tener al menos una
--- mecanica declarada, los tipos deben ser conocidos y los valores
--- numericos deben ser positivos.
--- @param mechanics any? el catalogo completo (`MechanicsByWorld`)
--- @param knownWorlds { string }? mundos validos
--- @return { string } problemas (lista vacia = todo cuadra)
function Rules.Audit(mechanics: any?, knownWorlds: { string }?): { string }
	local problems: { string } = {}

	if type(mechanics) ~= "table" then
		table.insert(problems, "catalogo invalido (no es tabla)")
		return problems
	end

	local worldSet: { [string]: boolean } = {}

	if knownWorlds then
		for _, id in ipairs(knownWorlds) do
			worldSet[id] = true
		end
	end

	for worldId, mech in pairs(mechanics) do
		if type(mech) ~= "table" then
			table.insert(problems, ("%s: definicion de mecanicas no es tabla"):format(worldId))
		else
			local hasMechanic = false

			if mech.Tracking then
				hasMechanic = true
			end

			if mech.NaturalMechanisms then
				hasMechanic = true
				for _, m in ipairs(mech.NaturalMechanisms) do
					if type(m) ~= "table" or type(m.Kind) ~= "string" then
						table.insert(problems, ("%s: mecanismo natural mal formado"):format(worldId))
					end
				end
			end

			if mech.TemporalEvents then
				hasMechanic = true
				for _, event in ipairs(mech.TemporalEvents) do
					if type(event) ~= "table" or type(event.Kind) ~= "string" then
						table.insert(problems, ("%s: evento temporal mal formado"):format(worldId))
					end
				end
			end

			if mech.BuriedTreasures then
				hasMechanic = true
			end

			if mech.Oases then
				hasMechanic = true
			end

			if mech.SlipperyIce then
				hasMechanic = true
			end

			if mech.FragilePlatforms then
				hasMechanic = true
			end

			if mech.MeteorShower then
				hasMechanic = true
			end

			if mech.Terminals then
				hasMechanic = true
			end

			if mech.SecurityDoors then
				hasMechanic = true
			end

			if mech.SecurityLasers then
				hasMechanic = true
			end

			if mech.DynamicRoutes then
				hasMechanic = true
			end

			if not hasMechanic then
				table.insert(problems, ("%s: sin mecanicas declaradas"):format(worldId))
			end
		end
	end

	if knownWorlds then
		for _, id in ipairs(knownWorlds) do
			if not mechanics[id] then
				table.insert(problems, ("%s: en WorldAccessRules pero no en MechanicsByWorld"):format(id))
			end
		end
	end

	return problems
end

return Rules
