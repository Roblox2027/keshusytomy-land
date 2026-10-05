--!strict
--[[
	BombPlacementRules
	Reglas PURAS de donde se puede colocar una bomba.

	EL BUG QUE RESUELVE
	-------------------
	El sintoma reportado era "la bomba se coloca en algunas posiciones del
	mapa y en otras no". La causa estaba en `BombService.detectArenaBounds`,
	que derivaba los limites de bomba de UNA sola pieza: `ArenaFloor`.

	Y `ArenaFloor` dejo de ser "la losa del mundo" en el commit que
	convirtio los cinco mundos en mundos con zonas y rutas: paso a ser el
	suelo de la ZONA DE ARENA, con un semilado minimo de 34 studs
	(`tools/worlds.js`, `ARENA_FLOOR_MIN_HALF`). El mundo entero son 11
	zonas y 19 rutas; la arena es UNA.

	El efecto es que el rectangulo de bombas cubria un fragmento pequeno
	del mundo y TODO lo demas se rechazaba con `OUTSIDE_ARENA`, en los
	cinco mundos por igual, incluidos el spawn y la entrada, que es donde
	el jugador aparece.

	QUE HACE, Y QUE NO HACE
	-----------------------
	Solo decide, con numeros, si un punto es una colocacion legal: si es
	finito, si cae dentro del area jugable del mundo y si esta a distancia
	razonable del personaje.

	No raycastea, no toca el Workspace y no concede nada. Eso lo hace
	`BombService`, que es quien tiene el motor; aqui solo vive la
	decision, y por eso se puede probar sin Roblox.

	LA REGLA DE JUEGO
	-----------------
	 maxima libertad dentro del espacio jugable + validacion segura.

	Se RECHAZA solo por una razon real de gameplay:
	  - la posicion no es un numero usable;
	  - esta fuera del area jugable del mundo;
	  - esta mas lejos que el rango de colocacion.

	NO se rechaza por una pared invisible, por una pieza antigua, por un
	filtro de raycast, por una altura concreta ni por que la zona de
	aplicacion se parezca a otra. Por eso el margen es holgado y por eso
	el area jugable la declara el mapa entero, no una pieza suelta.
]]

--- Caja en el plano XZ. La altura la decide otra regla.
export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

--- Una caja que se quiere sumar a la union del area jugable.
export type Box = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

--- Motivos de rechazo. Son CLAVES, no texto de jugador: el texto vive en
--- `BombService.REJECTION_REASONS`, que es lo que el jugador ve.
local Reject = {
	INVALID_POSITION = "INVALID_POSITION",
	OUTSIDE_ARENA = "OUTSIDE_ARENA",
	OUT_OF_RANGE = "OUT_OF_RANGE",
}

local Rules = {}

Rules.Reject = Reject

--- Margen alrededor del area jugable, en studs.
--
-- No es "por si acaso". El limite del mundo es el FINAL DEL TERRENO: se
-- corre, se acaba el suelo y se cae. Lo que no puede ser es una linea
-- pegada al ultimo metro de suelo, porque entonces cruzar una celda
-- contaria como salirse del mundo y el jugador leeria un muro invisible
-- donde no hay nada.
--
-- El margen coincide con el de `WorldBoundsRules` a proposito: las dos
-- reglas describen la MISMA frontera logica (donde acaba lo jugable) y
-- separarlas permitia que la bomba y el jugador tuvieran limites
-- distintos, que es exactamente la clase de bug que se corrige aqui.
Rules.Margin = 90

--- Une cajas en una sola. Devuelve nil si la lista esta vacia.
--
-- Es la operacion que falta en el servicio: el area jugable de un mundo
-- es la union de TODAS sus zonas y rutas, no el rectangulo de una pieza.
--- @param boxes { Box }?
--- @return Bounds?
function Rules.Union(boxes: { Box }?): Bounds?
	if not boxes or #boxes == 0 then
		return nil
	end

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for _, box in ipairs(boxes) do
		if box.minX < minX then
			minX = box.minX
		end
		if box.maxX > maxX then
			maxX = box.maxX
		end
		if box.minZ < minZ then
			minZ = box.minZ
		end
		if box.maxZ > maxZ then
			maxZ = box.maxZ
		end
	end

	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

--- Caja de una pieza ya colocada en el mundo.
--
-- `pad` es la holgura de la CAJA ENCLAVADA en XZ. Una losa girada 30
-- grados no cabe en `Size / 2`: usar solo la mitad del `Size` recorta
-- las esquinas y vuelve a crear el bug en las zonas que estan giradas.
--- @param x number
--- @param z number
--- @param sizeX number
--- @param sizeZ number
--- @param pad number?
--- @return Box
function Rules.BoxFromXZ(x: number, z: number, sizeX: number, sizeZ: number, pad: number?): Box
	local p = pad or 0

	return {
		minX = x - sizeX / 2 - p,
		maxX = x + sizeX / 2 + p,
		minZ = z - sizeZ / 2 - p,
		maxZ = z + sizeZ / 2 + p,
	}
end

--- Agranda (o reduce) una caja en el plano XZ.
--- @param bounds Bounds
--- @param margin number?
--- @return Bounds
function Rules.Expand(bounds: Bounds, margin: number?): Bounds
	local m = margin or Rules.Margin

	return {
		minX = bounds.minX - m,
		maxX = bounds.maxX + m,
		minZ = bounds.minZ - m,
		maxZ = bounds.maxZ + m,
	}
end

--- Anchura de una caja en XZ. Mide si el area jugable de un mundo es
--- REALmente un area y no un punto.
--- @param bounds Bounds
--- @return number
function Rules.Span(bounds: Bounds): number
	return math.max(bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ)
end

--- Un componente es un numero FINITO y utilizable.
---
--- `NaN` e `inf` son `number` en Luau: llegan por un payload manipulado o
--- por una operacion degenerada, y romperian la comparacion de rango.
--- @param value any
--- @return boolean
function Rules.IsUsableNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end

	if value ~= value then
		return false
	end

	return value ~= math.huge and value ~= -math.huge
end

--- Las tres componentes son numeros finitos y utilizables.
---
--- Se comprueba uno a uno y NO con un bucle sobre `{x, y, z}`: con una
--- tabla hueca (`position.x == nil`) `ipairs` se detiene en el primer hueco,
--- no recorre nada y devolveria `true`. Ese camino es real: es lo que llega
--- con un payload manipulado al que le falta una componente.
--- @param x any
--- @param y any
--- @param z any
--- @return boolean valid
function Rules.IsFinite(x: any, y: any, z: any): boolean
	return Rules.IsUsableNumber(x)
		and Rules.IsUsableNumber(y)
		and Rules.IsUsableNumber(z)
end

--- El punto cae dentro del area jugable (ya expandida).
--- @param bounds Bounds?
--- @param x number
--- @param z number
--- @return boolean
function Rules.IsInside(bounds: Bounds?, x: number, z: number): boolean
	-- Sin limites conocidos se acepta: un mundo sin suelo declarado no
	-- puede convertirse en un mundo donde no se puede jugar nada.
	if not bounds then
		return true
	end

	return x >= bounds.minX and x <= bounds.maxX and z >= bounds.minZ and z <= bounds.maxZ
end

--- Distancia en el plano XZ, que es la que decide el rechazo por rango.
--- @param ax number
--- @param az number
--- @param bx number
--- @param bz number
--- @return number
function Rules.FlatDistance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

--- Empuja un punto hasta estar a `minDistance` del personaje.
--
-- No rechaza: RECOLOCA. El jugador que pide la bomba justo donde esta no
-- quiere un error, quiere una bomba un poco mas alla; el minimo existe
-- para que la bomba no nazca DENTRO del personaje.
--- @param px number
--- @param pz number
--- @param tx number
--- @param tz number
--- @param minDistance number
--- @param fallbackX number?
--- @param fallbackZ number?
--- @return number x
--- @return number z
function Rules.SeparateFromPlayer(
	px: number,
	pz: number,
	tx: number,
	tz: number,
	minDistance: number,
	fallbackX: number?,
	fallbackZ: number?
): (number, number)
	local dx, dz = tx - px, tz - pz
	local distance = math.sqrt(dx * dx + dz * dz)

	if distance >= minDistance then
		return tx, tz
	end

	-- Direccion de separacion: la que venga del jugador. Si el cliente
	-- envia exactamente la posicion del jugador, se usa la mira, que es
	-- lo que evita dejar la bomba siempre detras.
	local ux, uz = dx / distance, dz / distance

	if distance < 0.01 then
		ux, uz = fallbackX or 1, fallbackZ or 0
	end

	local length = math.sqrt(ux * ux + uz * uz)

	if length < 0.01 then
		ux, uz = 1, 0
		length = 1
	end

	return px + (ux / length) * minDistance, pz + (uz / length) * minDistance
end

--- Altura final de la bomba sobre la superficie detectada.
--- @param groundY number
--- @param clearance number
--- @return number
function Rules.SettleHeight(groundY: number, clearance: number): number
	return groundY + clearance
end

--- Peticion de colocacion, ya medida por el servidor.
export type PlacementRequest = {
	--- Punto pedido: un `Vector3` del motor o una tabla `{x,y,z}`.
	position: any,
	playerX: number,
	playerY: number,
	playerZ: number,
	--- Limites del mundo (ya expandidos). nil = sin limites.
	bounds: Bounds?,
	--- Rango maximo desde el personaje.
	maxRange: number,
}

--- Decision de colocacion. Devuelve el PRIMER motivo y nunca concede nada.
--
-- El orden importa: primero se descarta lo que no es un numero, luego lo que
-- esta fuera del area jugable, y por ultimo lo que esta lejos. Un payload
-- manipulado se rechaza por la primera regla que falle, y no se sigue
-- mirando: seguir inspeccionando una peticion ya invalida solo amplia la
-- superficie de ataque.
--- @param request PlacementRequest
--- @return boolean accepted
--- @return string? reason clave de `Rules.Reject`
function Rules.Evaluate(request: PlacementRequest): (boolean, string?)
	local position = request.position

	-- `position` puede ser un `Vector3` del motor o una tabla `{x,y,z}`:
	-- los dos exponen `.x/.y/.z`, asi que la comprobacion util es la de los
	-- NUMEROS, no la del tipo de contenedor.
	if position == nil or not Rules.IsFinite(position.x, position.y, position.z) then
		return false, Rules.Reject.INVALID_POSITION
	end

	if not Rules.IsInside(request.bounds, position.x, position.z) then
		return false, Rules.Reject.OUTSIDE_ARENA
	end

	local distance = Rules.FlatDistance(
		request.playerX,
		request.playerZ,
		position.x,
		position.z
	)

	if distance > request.maxRange then
		return false, Rules.Reject.OUT_OF_RANGE
	end

	return true, nil
end

return Rules