--!strict
--[[
	WorldBoundsRules
	Reglas PURAS del limite logico de cada mundo.

	POR QUE ESTE MODULO
	------------------
	El borde del mundo es el FINAL DEL TERRENO. Se corre, se acaba el suelo, se
	cae, se muere y se reaparece. Lo que NO existe, y no debe existir, es una
	pared: la especificacion de este P0 prohibe expresamente el cuadrilatero
	artificial, y el verificador de navegabilidad daba PASS con 264-272 piezas
	`Border_Wall_*` por mundo que ceraban el mapa. Ese era el fallo: la caja era
	justo lo que hacia pasar el test.

	Como no hay pared, hace falta una RED DE SEGURIDAD LOGICA: saber cuando un
	jugador ha salido del area de juego. Y tiene que ser una regla, no una
	comparacion suelta en un servicio, para que se pueda probar sin motor.

	QUE HACE, Y QUE NO HACE
	-----------------------
	Solo decide si un punto esta dentro del area jugable de un mundo. No
	teletransporta, no mata y no toca ningun objeto del juego. La muerte por caida
	la decide el servidor comparando la altura con `GameConfig.FallDeathY`, que
	es una regla distinta: una es "estas fuera del mapa" y la otra "has caido".

	LA TOLERANCIA
	-------------
	El limite es la caja del terreno MAS un margen. El margen importa porque sin
	el el limite seria una linea pegada al ultimo suelo, y cruzar una celda
	contaria como salirse del mundo. El margen es de sobra para explorar el borde
	y crashing es lo que hay que hacer para morir: el jugador tiene que VER que
	el terreno se acaba, y eso lleva un recorrido, no un paso.
]]

--- Caja en el plano XZ: la del terreno o la logica (terreno mas margen).
export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

--- Punto del jugador en el plano XZ. La altura la decide otra regla.
export type Point2D = {
	x: number,
	z: number,
}

--- Punto con altura, para las preguntas que incluyen la caida.
export type Point3D = {
	x: number,
	y: number,
	z: number,
}

local WorldBoundsRules = {}

--- Margen de seguridad alrededor del terreno, en studs.
--
-- No es "por si acaso": es lo que convierte el limite en una red y no en una
-- trampa. Con el margen, el jugador puede llegar al ultimo metro de suelo,
-- dar la vuelta, comprobar que no hay nada mas y decide. Sin el margen, el
-- mismo recorrido lo mata en el ultimo paso, y la sensacion es exactamente la
-- que se quiere quitar: un muro invisible.
WorldBoundsRules.Margin = 90

--- Estados en los que puede estar un punto respecto del area jugable.
WorldBoundsRules.Zone = {
	-- Dentro del area de juego.
	Playable = "Playable",
	-- Fuera del area de juego, pero todavia dentro de la tolerancia: el jugador
	-- esta en el limite y puede volver andando.
	Margin = "Margin",
	-- Fuera del area de juego y de la tolerancia.
	OutOfBounds = "OutOfBounds",
}

--- Caja jugable de un mundo a partir de la caja de su terreno.
--
-- El terreno es lo que el generador construye (zonas y rutas); la caja que
-- llega aqui es la de esas piezas. La funcion devuelve la caja LOGICA, que es
-- la del terreno mas el margen.
--
-- @param bounds Bounds
-- @param margin number? margen; por defecto `WorldBoundsRules.Margin`
-- @return Bounds
function WorldBoundsRules.WithMargin(bounds: Bounds, margin: number?): Bounds
	local m = margin or WorldBoundsRules.Margin
	return {
		minX = bounds.minX - m,
		maxX = bounds.maxX + m,
		minZ = bounds.minZ - m,
		maxZ = bounds.maxZ + m,
	}
end

--- Clasifica un punto respecto de la caja jugable.
--
-- @param bounds caja logica (`WithMargin`)
-- @param position Point2D (se usa XZ: la altura no limita)
-- @param tolerance number? margen adicional de toleracia
-- @return string estado de `WorldBoundsRules.Zone`
function WorldBoundsRules.Classify(bounds: Bounds, position: Point2D, tolerance: number?): string
	local t = tolerance or 0

	if position.x < bounds.minX - t or position.x > bounds.maxX + t then
		return WorldBoundsRules.Zone.OutOfBounds
	end
	if position.z < bounds.minZ - t or position.z > bounds.maxZ + t then
		return WorldBoundsRules.Zone.OutOfBounds
	end
	if position.x < bounds.minX or position.x > bounds.maxX then
		return WorldBoundsRules.Zone.Margin
	end
	if position.z < bounds.minZ or position.z > bounds.maxZ then
		return WorldBoundsRules.Zone.Margin
	end

	return WorldBoundsRules.Zone.Playable
end

--- ¿El punto ha salido del area jugable de su mundo?
--
-- Es la pregunta que hace el servidor. La respuesta NO dispara ninguna accion:
-- el jugador cae, y la muerte la decide la altura. Aqui solo se marca el estado,
-- que es lo que permite avisar y lo que despues comprueba la QA.
--
-- @param bounds caja logica del mundo
-- @param position Point2D (la altura no limita: la cuenta la caida)
-- @param tolerance number?
-- @return boolean
function WorldBoundsRules.IsOutOfBounds(bounds: Bounds, position: Point2D, tolerance: number?): boolean
	return WorldBoundsRules.Classify(bounds, position, tolerance)
		== WorldBoundsRules.Zone.OutOfBounds
end

--- Margen que hace falta para que el limite NO sea una trampa.
--
-- Devuelve cuanto tendria que crecer el margen para que un jugador que sale
-- andando del terreno tarde mas de `minSeconds` en cruzarlo a 16 studs por
-- segundo. Es la regla que convierte "el margen es suficiente" en un numero
-- medido en vez de en una opinion.
--
-- @param walkSpeed number studs por segundo
-- @param minSeconds number
-- @return number margen necesario, en studs
function WorldBoundsRules.RequiredMargin(walkSpeed: number, minSeconds: number): number
	if walkSpeed <= 0 or minSeconds <= 0 then
		return 0
	end
	return walkSpeed * minSeconds
end

return WorldBoundsRules