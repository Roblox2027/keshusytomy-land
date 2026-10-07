--!strict
--[[
	AudioRules
	Logica PURA de DECIDIR QUE SUENA.

	POR QUE HACE FALTA
	------------------
	El problema del audio no es reproducir: es no reproducir de mas. Un
	juego con veinte monstruos, cuatro ambientes y una explosion abre
	cientos de sonidos a la vez, y el cliente se atasca justo en el momento
	mas importante: la explosion.

	Ademas, sin jerarquia, los pasos y el viento TAPAN la bomba, el ataque
	y el cambio de fase del jefe. El jugador oye "algo" pero no sabe que ha
	pasado.

	Este modulo decide, con reglas comprobables, si un sonido debe sonar:

	    categoria  -> volumen y prioridad
	    distancia  -> si se oye y con que atenuacion
	    enfriamiento -> si ya ha sonado hace poco

	Nada de esto necesita el motor, asi que se prueba entero con
	`luau.exe`. El `AudioController` solo aplica lo que aqui se decide.

	LA REGLA DE NEGOCIO
	-------------------
	Si algo importante se ve, tambien se siente. Y si algo importante se
	mueve, lo comunica visual y/o auditivamente. Eso obliga a que CADA
	accion de juego tenga entrada en `AudioConfig.Events`, y a que el
	volumen de una explosion no dependa de que sonido este sonando antes.
]]

local Rules = {}

export type MusicContext = {
	WorldId: string?,
	Danger: boolean?,
	Combat: boolean?,
	Boss: boolean?,
	Victory: boolean?,
	Defeat: boolean?,
}

--- Selects the highest-priority music state from server-published gameplay context.
--- @param context MusicContext
--- @return string
function Rules.SelectMusicState(context: MusicContext): string
	if type(context.WorldId) ~= "string" or context.WorldId == "Lobby" then
		return "Lobby"
	end
	if context.Defeat == true then
		return "Defeat"
	end
	if context.Victory == true then
		return "Victory"
	end
	if context.Boss == true then
		return "Boss"
	end
	if context.Combat == true then
		return "Combat"
	end
	if context.Danger == true then
		return "Danger"
	end
	return "Exploring"
end

--- CATEGORIAS de audio.
---
--- No son etiquetas: cada una tiene volumen y prioridad, y las dos se
--- aplican al reproducir. Mezclarlas en una sola seria volver a tener "un
--- solo Sound" para todo, que es justo lo que se quiere evitar.
Rules.Category = {
	-- MUSICA: fondo. Nunca tapa nada porque es la de menor prioridad.
	Music = "Music",
	-- EFECTOS: lo que el jugador hace y lo que le pasa.
	Sfx = "Sfx",
	-- AMBIENTE: viento, agua, zumbidos. Son MUCHOS y son de fondo.
	Ambient = "Ambient",
	-- INTERFAZ: clics, confirmaciones, aperturas de menu.
	UI = "UI",
	-- CRIATURAS: respiraciones, rugidos, chillidos. Su propia categoria
	-- porque son la IDENTIDAD de cada monstruo y no un efecto suelto.
	Voice = "Voice",
}

--- PRIORIDAD por categoria. Mas alto = mas importante.
---
--- El numero no es decorativo: `Rules.Compare` lo usa para decidir a quien
--- se corta cuando dos sonidos compiten por la misma ranura del pool.
Rules.Priority = {
	Music = 0,
	Ambient = 1,
	UI = 2,
	Voice = 3,
	Sfx = 4,
}

--- VOLUMEN por categoria, antes de aplicar el maestro.
Rules.Volume = {
	Music = 0.35,
	Ambient = 0.5,
	UI = 0.8,
	Voice = 0.9,
	Sfx = 1.0,
}

--- Volumen maestro. Se aplica AL FINAL, a todo.
Rules.MasterVolume = 0.85

--- Enfriamiento MINIMO por categoria, en segundos.
---
--- Es lo que impide el spam. Sin esto, un enemigo que reproduce su paso
--- cada frame abriria un `Sound` por frame; con esto, uno cada 0.4 s como
--- mucho.
---
--- `Sfx` tiene el mas CORTO porque contiene la explosion y el dano, que no
--- pueden esperar. `Ambient` el mas largo porque nada de lo que pasa en el
--- ambiente es urgente.
Rules.Cooldown = {
	Music = 1,
	Ambient = 2.5,
	UI = 0.05,
	Voice = 0.35,
	Sfx = 0.08,
}

--- Margen de comparacion para instantes.
---
--- `100 + 0.35 - 100` no es exactamente `0.35` en coma flotante. Sin este
--- margen, un sonido que "ya puede" sonaria "todavia no" y el
--- comportamiento dependeria de la suma de dos numeros en vez de del
--- diseno. Solo afecta al limite, nunca al dia a dia.
Rules.Epsilon = 0.0001

--- Fraccion del alcance a la que el sonido aun suena a VOLUMEN PLENO.
---
--- No es un detalle: sin ella, una bomba colocada encima del jugador
--- sonaria al 99 % del volumen, y un sonido de explosion siempre suena algo
-- sospechoso de sonar "apagado" cerca de donde pasa.
Rules.FullVolumeRatio = 0.1

--- Distancia maxima a la que se oye un sonido, en studs.
---
--- `Sfx` oye lejos porque la explosion es informacion de juego: tiene que
--- llegar aunque no la estes mirando. `Ambient` oye corto porque el viento
--- de al lado de donde estas no es el del mapa entero.
Rules.MaxDistance = {
	Music = math.huge,
	Ambient = 90,
	UI = math.huge,
	Voice = 140,
	Sfx = 260,
}

--- Devuelve el volumen final de una categoria.
---
--- Se aplican las TRES capas: volumen de categoria, volumen de la propia
--- pista (si lo indica la llamada) y volumen maestro.
---
--- @param category string
--- @param trackVolume number? volumen especifico de la pista, 0..1
--- @param master number? volumen maestro, 0..1
--- @return number volume 0..1
function Rules.ResolveVolume(category: string, trackVolume: number?, master: number?): number
	-- `base` se anota como `number` de forma explicita. Luau deduce
	-- `unknown` al indexar `Rules.Volume[category]`, y a partir de ahi la
	-- multiplicacion falla con "no hay sobrecarga para __mul".
	local base: number = Rules.Volume[category]

	if base == nil then
		-- Una categoria desconocida cae en `Sfx`: es la unica que siempre
		-- existe y la mas audible. Silenciar un sonido desconocido seria
		-- peor que reproducirlo de mas.
		base = Rules.Volume[Rules.Category.Sfx]
	end

	local track = if type(trackVolume) == "number" then trackVolume else 1
	local masterLevel = if type(master) == "number" then master else Rules.MasterVolume

	-- Se ACOTAN LAS ENTRADAS por separado y no solo el producto. Sin esto,
	-- `track = -1` y `master = -1` se multiplicarian y darian `+1`: un
	-- volumen NEGATIVO (un dato corrupto o un slider al reves) sonaria AL
	-- MAXIMO en vez de callarse. Acotar solo el producto no lo detecta,
	-- porque `(-1) * (-1) = 1`.
	local safeTrack = math.clamp(track, 0, 1)
	local safeMaster = math.clamp(masterLevel, 0, 1)

	-- Acotado a 0..1: un `Volume` mayor que 1 en Roblox recorta y hace que
	-- el audio suene "roto" en vez de "fuerte".
	return math.clamp(base * safeTrack * safeMaster, 0, 1)
end

--- Aplica el maestro a un volumen ya resuelto.
--- @param volume number
--- @param master number?
--- @return number
function Rules.ApplyMaster(volume: number, master: number?): number
	local masterLevel = if type(master) == "number" then master else Rules.MasterVolume
	return math.clamp(volume * masterLevel, 0, 1)
end

--- Prioridad de una categoria.
--- @param category string
--- @return number
function Rules.GetPriority(category: string): number
	return Rules.Priority[category] or Rules.Priority[Rules.Category.Sfx]
end

--- Compara dos categorias por prioridad.
---
--- Se usa cuando dos sonidos compiten por la misma ranura del pool: el mas
--- importante se queda y el otro se recorta. Sin esta comparacion, un paso
--- puede robar la ranura de una explosion.
---
--- @param incoming string categoria que quiere sonar
--- @param resident string categoria que ya esta sonando
--- @return boolean incomingWins
function Rules.Compare(incoming: string, resident: string): boolean
	local a = Rules.GetPriority(incoming)
	local b = Rules.GetPriority(resident)

	if a ~= b then
		return a > b
	end

	-- Misma prioridad: gana el nuevo. Es lo mas simple y evita que un
	-- sonido se auto-bloquee por ser el primero de su categoria.
	return true
end

--- Distancia a la que se oye un sonido de una categoria.
--- @param category string
--- @return number
function Rules.GetMaxDistance(category: string): number
	return Rules.MaxDistance[category] or Rules.MaxDistance[Rules.Category.Sfx]
end

--- Comprueba si un sonido se oye a una distancia dada.
---
--- Es el corte que evita que veinte Slimes a 400 studs llenen el cliente de
--- sonidos que nadie oye.
---
--- @param category string
--- @param distance number
--- @return boolean audible
function Rules.IsAudible(category: string, distance: number): boolean
	if distance < 0 then
		-- Una distancia negativa es un dato corrupto (una posicion sin
		-- resolver). Se trata como "se oye": el sonido es real y callarlo
		-- seria peor que arriesgar uno de mas.
		return true
	end

	return distance <= Rules.GetMaxDistance(category)
end

--- Atenuacion por distancia, de 1 (encima) a 0 (en el limite).
---
--- No es una cuenta lineal: usa el CUADRADO de la distancia normalizada.
--- Con una lineal, un sonido a la mitad del alcance suena la mitad y se
--- oye igual que uno lejano en un mundo ruidoso. Con la cuadratica, el
--- cercano manda y el lejano se pierde, que es lo que pasa de verdad en un
--- mundo con viento.
---
--- @param distance number
--- @param maxDistance number
--- @return number factor 0..1
function Rules.Attenuation(distance: number, maxDistance: number): number
	if maxDistance <= 0 or maxDistance == math.huge then
		-- Sin limite (musica, interfaz): no hay atenuacion.
		return 1
	end

	if distance >= maxDistance then
		return 0
	end

	if distance <= 0 then
		return 1
	end

	local normalized = distance / maxDistance

	-- RADIO PLENO.
	--
	-- A muy poca distancia el sonido NO se atenua. Sin este margen, un
	-- sonido a 10 studs de un alcance de 100 suena al 99 %: una perdida
	-- imperceptible en el volumen pero que hace que el propio sonido de
	-- una bomba junto al jugador no llegue a sonar entero.
	--
	-- El 10 % del alcance es el punto: bastante para que el jugador note
	-- que esta encima, poco para que un explosion cercana no tenga nada de
	-- cuerpo.
	if normalized <= Rules.FullVolumeRatio then
		return 1
	end

	-- Cuadratica sobre el resto: el punto medio del tramo restante queda
	-- alto, de modo que el cercano manda y el lejano se pierde, que es lo
	-- que pasa de verdad en un mundo con viento.
	local remapped = (normalized - Rules.FullVolumeRatio) / (1 - Rules.FullVolumeRatio)
	return 1 - (remapped * remapped)
end

--- Enfriamiento de una categoria.
--- @param category string
--- @return number seconds
function Rules.GetCooldown(category: string): number
	return Rules.Cooldown[category] or Rules.Cooldown[Rules.Category.Sfx]
end

--- Indica si un sonido puede reproducirse segun su enfriamiento.
---
--- Es la funcion que evita el spam de pasos. El estado de "cuando sono la
--- ultima vez" lo lleva el controller; aqui solo esta la regla.
---
--- @param category string
--- @param lastPlayedAt number os.clock de la ultima vez, o -1 si nunca
--- @param now number os.clock actual
--- @return boolean allowed
--- @return number remaining segundos que faltan
function Rules.CheckCooldown(category: string, lastPlayedAt: number, now: number): (boolean, number)
	local cooldown = Rules.GetCooldown(category)

	-- `lastPlayedAt < 0` significa "nunca ha sonado": no hay nada que
	-- esperar. Sin esta rama, la primera vez que suena algo el controller
	-- tendria que inventar un instante pasado.
	if lastPlayedAt < 0 then
		return true, 0
	end

	local elapsed = now - lastPlayedAt

	-- El margen evita que `100 + 0.35 - 100` (que da 0.34999...) se lea
	-- como "todavia no ha pasado el enfriamiento". Solo cambia el limite.
	if elapsed >= cooldown - Rules.Epsilon then
		return true, 0
	end

	return false, cooldown - elapsed
end

return Rules
