--!strict
--[[
	ZoneRules
	ZONAS ACTIVAS y LOD logico (FASES 7 y 13).

	EL PROBLEMA
	-----------
	El enunciado pide mundos "significativamente mas grandes" y, a la vez,
	prohibe "miles de NPC activos" y "IA permanente fuera del area del jugador".
	Las dos cosas son la misma condicion: un mundo grande solo es jugable si lo
	que esta lejos del jugador hace ALGO distinto de lo que esta cerca.

	Por eso una zona no es un rectangulo decorativo: es una unidad de trabajo con
	tres estados, y cambiar de estado es lo que hace que el mapa pueda crecer sin
	que el coste de IA crezca con el.

	POR QUE UN SOLO SISTEMA DE ZONAS
	-------------------------------
	El mapa del generador ya tiene zonas con el mismo identificador (`Hollow`,
	`Arena`, `Grooty`...). Este modulo NO las duplica: las consume por nombre. Si
	hubiera dos listas de zonas, la del generador y la del servidor, el servicio
	buscaria `Hollow` en su propia tabla y no encontraria nada, y el mapa grande
	funcionaria sin enemigos.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- NIVELES DE DETALLE
-- ---------------------------------------------------------------------------

Rules.Lod = {
	-- Zona abandonada. El SERVICE no hace spawn aqui y los enemigos que quedaran
	-- se retiran. Es el estado por defecto de todo lo que el jugador no ve.
	Dormant = "Dormant",
	-- Zona cercana: IA completa, spawns activos, eventos. Lo que el jugador
	-- esta viviendo.
	Active = "Active",
	-- Zona a media distancia: la geometria sigue ahi, pero sin IA completa ni
	-- repoblado. Sirve para que el jugador vea que hay contenido mas adelante
	-- sin que ese contenido le cueste.
	Near = "Near",
}

-- ---------------------------------------------------------------------------
-- DISTANCIAS
-- ---------------------------------------------------------------------------
--
-- El criterio es la distancia entre la ZONA y el jugador, no la distancia de
-- cada enemigo. Medir por zonas es lo que hace el sistema barato: con veinte
-- zonas son veinte comparaciones por jugador y por tick, en vez de una por
-- enemigo. A mil enemigos, la diferencia es de tres ordenes de magnitud, y es
-- la razon por la que esto no se implementa enemigo a enemigo.

--- Distancia a la que una zona pasa a `Active`, en studs.
Rules.ActiveDistance = 220

--- Distancia a la que una zona deja de estar `Near` y vuelve a `Dormant`.
Rules.DormantDistance = 480

--- Margen de HISTERESIS.
---
--- Sin el, una zona al borde del radio oscila entre `Active` y `Near` cada vez
--- que el jugador da un paso, y cada oscilacion dispara y retira enemigos. Un
-- margen del 15 % hace que el cambio de estado tenga que superarse DEL TODO
-- para ocurrir, que es lo que evita ese vaiven.
Rules.Hysteresis = 0.15

--- Nivel de detalle de una zona a una distancia dada.
---
--- @param distance number distancia del jugador a la zona, en studs
--- @param current string? estado actual (para la histeresis)
--- @return string lod
function Rules.LodAt(distance: number, current: string?): string
	local d = tonumber(distance)

	-- Una distancia no numerica (un `nil` de una zona recien creada) se trata
	-- como lejana: arrancar DESPIERTO es la opcion segura. Arrancar activo es
	-- la que llena el servidor de enemigos que nadie mira.
	if not d or d ~= d then
		return Rules.Lod.Dormant
	end

	-- La histeresis se aplica al SALIR de la zona activa, venga del estado que
	-- venga. Sin esto, un jugador que cruza el umbral de `ActiveDistance` hacia
	-- fuera pasaria de `Active` a `Dormant` de golpe, cuando lo correcto es que
	-- pase por `Near`: el mismo borde que ha dado problemas con las hordas al
	-- aparecer y desaparecer sin previo aviso.
	if current == Rules.Lod.Near or current == Rules.Lod.Active then
		local limit = Rules.DormantDistance * (1 + Rules.Hysteresis)

		if d <= limit then
			-- Pero solo se degrada un escalon: si venia de `Active` y ya esta
			-- fuera del radio activo, pasa a `Near`, no se queda `Active`.
			if d <= Rules.ActiveDistance then
				return Rules.Lod.Active
			end

			return Rules.Lod.Near
		end
	end

	if d <= Rules.ActiveDistance then
		return Rules.Lod.Active
	end

	if d <= Rules.DormantDistance then
		return Rules.Lod.Near
	end

	return Rules.Lod.Dormant
end

--- Una zona debe ejecutar IA completa.
--- @param lod string
--- @return boolean
function Rules.HasFullAI(lod: string): boolean
	return lod == Rules.Lod.Active
end

--- Una zona debe repoblarse.
---
--- `Near` NO repuebla. Esa es la distincion economica importante del sistema:
--- `Near` es el estado que permite que un mapa grande exista, porque el jugador
--- ve que hay zona alrededor sin que esas zonas generen NPC.
---
--- Si `Near` repoblara, un mundo de veinte zonas mantendria enemigos en las
--- dieciseis lejanas y el limite global se gastaria en contenido que nadie ve.
--- @param lod string
--- @return boolean
function Rules.ShouldPopulate(lod: string): boolean
	return lod == Rules.Lod.Active
end

--- Una zona puede generar eventos.
--- @param lod string
--- @return boolean
function Rules.CanHostEvent(lod: string): boolean
	return lod == Rules.Lod.Active
end

-- ---------------------------------------------------------------------------
-- POBLACION POR ZONA (FASE 11)
-- ---------------------------------------------------------------------------

--- Poblacion MINIMA y MAXIMA de una zona, en dia y en noche.
---
--- Es lo que responde al ejemplo del enunciado (`Forest/DeepForest`: 2-5 de dia,
--- 6-12 de noche) sin que la logica este escrita a mano en cada zona.
---
--- Las tres razones por las que son MINIMO y MAXIMO y no una cantidad fija:
---
---   1. El minimo evita que una zona explorada se quede vacia para siempre. Sin
---      minimo, la primera vez que el jugador limpia la zona, ya no vuelve a
---      tener nada y no tiene motivo para volver.
---   2. El maximo es el limite de RENDIMIENTO por zona. El global existe
---      (`PopulationLimits`), pero el global solo protege el servidor: el
---      maximo por zona protege la LEGIBILIDAD, que es otra cosa.
---   3. La noche sube el maximo pero NO el minimo por la misma razon que baja
---      la cantidad de enemigos en el mundo real: de noche hay mas presion, no
---      mas enemigos garantizados. Subir el minimo de noche llenaria el mapa de
---      enemigos donde no hay jugador, que es gasto sin percepcion.
Rules.PopBase = { Min = 2, Max = 5 }
Rules.PopNight = { Min = 2, Max = 12 }

--- Multiplicadores de poblacion por el ROL de la zona.
---
--- El rol ya existe en el mapa del generador y es la misma distincion de
--- contenido que usa el propio generador para poner destructibles y peligros.
--- Reutilizarlo evita inventar una taxonomia paralela que el mapa no tiene.
Rules.PopByRole = {
	entrance = { Min = 0, Max = 2 },
	exploration = { Min = 2, Max = 5 },
	scenic = { Min = 1, Max = 4 },
	encounter = { Min = 3, Max = 7 },
	destruction = { Min = 2, Max = 5 },
	intermediate = { Min = 2, Max = 6 },
	reward = { Min = 1, Max = 3 },
	secret = { Min = 1, Max = 4 },
	event = { Min = 0, Max = 6 },
	miniboss = { Min = 2, Max = 5 },
	boss = { Min = 1, Max = 3 },
	arena = { Min = 3, Max = 8 },
	exit = { Min = 0, Max = 2 },
}

--- Tope de enemigos en UNA zona.
---
--- Es el limite que hace que un mundo grande siga siendo un mundo grande y no
--- un almacen de NPC. Se declara aparte de `PopulationLimits.MaxPerWorld`
--- porque llenar el maximo de cinco mundos a la vez no es aceptable en un
--- servidor normal.
Rules.MaxPerZone = 24

--- Poblacion de una zona para una noche y un estado del ciclo.
---
--- @param role any rol de la zona (ver `PopByRole`)
--- @param night any
--- @param isNight boolean? forzar la fase nocturna
--- @return { Min: number, Max: number }
function Rules.PopulationFor(role: any, night: any, isNight: boolean?): { Min: number, Max: number }
	local base = Rules.PopByRole[role] or Rules.PopBase
	local n = tonumber(night)

	if not n or n ~= n then
		n = 1
	end

	n = math.clamp(n, 1, 99)

	-- El crecimiento con la noche es el de la BANDA, no lineal: el enunciado
	-- quiere que las noches altas cambien de CARACTER, no solo de cantidad, y
	-- la banda es donde vive esa caracterizacion.
	local t = (n - 1) / 98
	local nightScale = 1 + t * 1.8

	local min = base.Min
	local max = base.Max

	if isNight then
		-- El minimo NUNCA sube por la noche: obligar a mantener enemigos donde
		-- no hay jugador es gasto que el jugador no percibe.
		min = math.min(base.Min, Rules.PopNight.Min)
		max = math.floor(math.max(base.Max, Rules.PopNight.Max) * nightScale)
	end

	max = math.min(max, Rules.MaxPerZone)

	return {
		Min = math.clamp(math.floor(min), 0, max),
		Max = math.clamp(math.floor(max), 0, Rules.MaxPerZone),
	}
end

-- ---------------------------------------------------------------------------
-- CONTABILIDAD GLOBAL (FASE 12)
-- ---------------------------------------------------------------------------

--- Limites de la poblacion viva del servidor.
---
--- Estos son los TOPES DUROS. Las poblaciones por zona son objetivos; estos son
--- techos, y son los que evitan que un jugador que entra en varios mundos con
--- la poblacion dinamica activa tumbe el servidor.
Rules.PopulationLimits = {
	MaxTotal = 60,
	MaxPerWorld = 30,
	MaxPerZone = 24,
	MaxPerPlayer = 12,
}

--- Exceso de enemigos, en piezas.
---
--- Se devuelven AMBOS criterios en una tabla porque son problemas DISTINTOS: si
--- el global esta bien pero el mundo no, el exceso es del mundo, y podar en otra
--- zona del MISMO mundo lo resuelve igual. Un unico numero obligaria al
--- servicio a decidir donde podar sin saber cual de los dos limites fallo.
--- @param inWorld number enemigos vivos en el mundo
--- @param inTotal number enemigos vivos en todo el servidor
--- @param worldLimit any? techo del mundo
--- @param globalLimit any? techo global
--- @return { World: number, Total: number, Excess: number }
function Rules.Overflow(
	inWorld: number,
	inTotal: number,
	worldLimit: any?,
	globalLimit: any?
): { World: number, Total: number, Excess: number }
	local worldCap = tonumber(worldLimit) or Rules.PopulationLimits.MaxPerWorld
	local globalCap = tonumber(globalLimit) or Rules.PopulationLimits.MaxTotal

	local w = tonumber(inWorld) or 0
	local t = tonumber(inTotal) or 0

	if w ~= w then
		w = 0
	end
	if t ~= t then
		t = 0
	end

	local byWorld = math.max(0, w - worldCap)
	local byTotal = math.max(0, t - globalCap)

	return {
		World = byWorld,
		Total = byTotal,
		Excess = math.max(byWorld, byTotal),
	}
end

--- Resolucion FINAL de la poblacion objetivo de una zona.
---
--- Esta es la funcion que el servicio llama cuando decide poblar. Aplica, en
--- este orden: el objetivo por rol, noche y fase; despues el limite por zona;
--- despues el presupuesto que queda.
---
--- El orden importa: si se aplicara el presupuesto primero, una zona podria
--- pedir ocho y quedarse con cero porque otra zona se llevo el presupuesto, y
--- el jugador veria una zona "vacia" justo al lado.
---
--- @param role any
--- @param night any
--- @param isNight boolean?
--- @param budget any? presupuesto restante
--- @return number objetivo de enemigos para la zona
function Rules.ResolvePopulation(role: any, night: any, isNight: boolean?, budget: any): number
	local pop = Rules.PopulationFor(role, night, isNight)
	local target = pop.Max

	local remaining = tonumber(budget)

	if remaining and remaining == remaining then
		target = math.min(target, math.floor(remaining))
	end

	return math.max(0, math.min(target, Rules.MaxPerZone))
end

return Rules
