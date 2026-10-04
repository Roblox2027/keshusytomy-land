--!strict
--[[
	MonsterScaleRules
	TAMANO de los monstruos, separado del modelo y de la hitbox.

	EL PROBLEMA QUE RESUELVE
	------------------------
	Un enemigo del mismo tamano que el jugador no se lee como amenaza: es
	una caja de color del mismo alto que tu personaje, y el cerebro lo
	clasifica como "otra cosa" y no como "algo que me puede matar".

	Aumentar el MODELO es facil. Lo que no es facil es hacerlo sin romper
	el juego, porque el modelo y la colision se confundieron durante mucho
	tiempo: un Guardian del doble de alto que colisiona con su modelo
	visual no se puede rodear, se atascan sus piernas en los escalones y no
	entra por los huecos que el mapa revela al usar bombas.

	Por eso aqui hay DOS numeros y no uno:
	- `VisualScale`  multiplica lo que se VE.
	- `HitboxScale`  multiplica lo que COLISIONA.

	Se calibran por separado y ambos se acotan. Un `HitboxScale` de 1.0 con
	un `VisualScale` de 2.0 significa "monstruo enorme que se puede
	atravesar", y uno de 2.0 significa "monstruo enorme que bloquea los
	pasillos": los dos extremos rompen algo. El valor intermedio es el que
	se quiere.

	LA REGLA DE DISENO
	------------------
	Con el jugador a `Height = 1.0`, los rangos son:

	    Slime        1.3 - 1.5
	    Bomb Bug     1.3 - 1.5
	    Shadow       1.4 - 1.7
	    Fire Beast   1.6 - 2.0
	    Ice Beast    1.6 - 2.0
	    Bomber       1.5 - 1.9
	    Hunter       1.4 - 1.7
	    Guardian     1.9 - 2.4

	Se comprueba con `AssertDesign` y en `MonsterScale.spec`: si un
	monstruo nuevo se declara por debajo de 1.2, la prueba falla. Es la
	forma de que "el enemigo no se ve mayor que el jugador" no vuelva a
	ser un descuido.
]]

local Rules = {}

--- Escala visual por monstruo, dentro de los rangos de diseno.
---
--- Es una COPIA de los valores declarados en `MonsterDefinitions`, y esa
--- duplicacion es DELIBERADA: `MonsterDefinitions` es un modulo que se
--- carga con stubs de color en las pruebas y aqui solo vive aritmetica.
--- `MonsterScale.spec` comprueba que las dos tablas COINCIDEN, de modo que
--- si alguien cambia un valor en un sitio y no en el otro, el fallo sale
--- en las pruebas y no en un playtest.
Rules.VisualScale = {
	Slime = 1.4,
	BombBug = 1.4,
	Shadow = 1.55,
	Hunter = 1.55,
	Guardian = 2.1,
	IceBeast = 1.8,
	FireBeast = 1.9,
	BomberMonster = 1.7,
	CyberStalker = 1.65,
}

--- Rango permitido por monstruo. Sirve para VALIDAR, no para construir.
Rules.Ranges = {
	Slime = { 1.3, 1.5 },
	BombBug = { 1.3, 1.5 },
	Shadow = { 1.4, 1.7 },
	Hunter = { 1.4, 1.7 },
	Guardian = { 1.9, 2.4 },
	IceBeast = { 1.6, 2.0 },
	FireBeast = { 1.6, 2.0 },
	BomberMonster = { 1.5, 1.9 },
	CyberStalker = { 1.4, 1.8 },
}

--- Multiplicador de ESCALA POR MUNDO.
---
--- Es lo que hace que la dificultad se comunique sin retocar cada bicho:
--- el Forest apenas agranda a sus enemigos y el Cyber los empuja. Los
--- valores crecen POCO a proposito: un Guardian de 2.1 en Forest y de 2.4 en
--- Cyber ya empieza a no caber por algunos huecos, y el jugador acabaria
--- sin poder usar la bomba en la parte del mapa que el Guardian tiene
--- delante.
Rules.WorldScale = {
	Forest = 0.95,
	Desert = 1.0,
	Ice = 1.05,
	Volcano = 1.1,
	Cyber = 1.15,
}

--- Escala por defecto de un monstruo del que no se sabe nada.
Rules.DefaultVisualScale = 1.5

--- Proporcion de HITBOX por defecto respecto al modelo.
---
--- 0.72 es el punto medio razonable: la raiz invisible es un 28 % mas
--- pequena que lo que se ve. Suficiente para que las patas del Guardian
--- "metan" en el hueco sin que se note, y suficiente para que el jugador no
--- atraviese un bicho de 2.1 de alto sin notar nada.
Rules.DefaultHitboxRatio = 0.72

--- Hitbox por monstruo, cuando un bicho necesita la suya.
---
--- Un Guardian con hitbox estandar se puede empujar con una bomba; con 0.85
--- hace falta apartarse de verdad. Es la diferencia entre "estorbo" y
--- "muro".
Rules.HitboxRatio = {
	Guardian = 0.85,
	FireBeast = 0.8,
	IceBeast = 0.8,
	Slime = 0.65,
}

--- Tope de la hitbox, en multiplos del modelo.
---
--- Es el freno que impide el segundo fallo: una hitbox que llega al
--- propio tamano del modelo deja de poder rodearse en un pasillo estrecho.
Rules.MaxHitboxRatio = 0.85

--- Suelo de la hitbox, en multiplos del modelo.
---
--- El otro freno: una hitbox microscopica haria que las bombas "pasaran"
--- "por debajo" del monstruo sin danarlo, y el jugador veria como explota a
--- su lado sin que el bicho reaccionase.
Rules.MinHitboxRatio = 0.55

--- Multiplicador de mundo para un mundo desconocido.
Rules.DefaultWorldScale = 1.0

--- Escala visual de un identificador de monstruo.
--- @param id string
--- @return number
function Rules.GetVisualScale(id: string): number
	return Rules.VisualScale[id] or Rules.DefaultVisualScale
end

--- Multiplicador de mundo.
--- @param worldId string?
--- @return number
function Rules.GetWorldScale(worldId: string?): number
	if worldId == nil then
		return Rules.DefaultWorldScale
	end

	return Rules.WorldScale[worldId] or Rules.DefaultWorldScale
end

--- Escala visual FINAL de un monstruo, ya con el mundo aplicado.
---
--- Es la unica funcion que hay que usar para dibujar: aplicar el mundo en
--- un sitio y no en otro es como dos monstruos del mismo tipo salen con
--- tamanos distintos dentro del mismo mundo.
---
--- @param id string
--- @param worldId string?
--- @return number
function Rules.Resolve(id: string, worldId: string?): number
	return Rules.GetVisualScale(id) * Rules.GetWorldScale(worldId)
end

---- Proporcion de HITBOX de un monstruo.
---
--- Devuelve un valor RELATIVO al modelo (0..1), no absoluto: quien llama
--- lo multiplica por el tamano del modelo que ya ha construido.
---
--- El valor NO crece con el mundo, y esa es la decision importante: el
--- mundo cambia lo grande que se ve el bicho, pero no lo grande que se
--- puede colisionar. Si creciera, el Guardian del Cyber bloquearia
--- pasillos que el Guardian del Forest deja pasar, y la diferencia entre
--- mundos seria "este mapa no se puede jugar".
---
--- @param id string
--- @return number ratio
function Rules.GetHitboxRatio(id: string): number
	local declared = Rules.HitboxRatio[id]
	local base = if type(declared) == "number" then declared else Rules.DefaultHitboxRatio

	if base > Rules.MaxHitboxRatio then
		return Rules.MaxHitboxRatio
	end

	if base < Rules.MinHitboxRatio then
		return Rules.MinHitboxRatio
	end

	return base
end

--- Hitbox ABSOLUTA a partir de un tamano de modelo.
--- @param modelSize Vector3 tamano del modelo ya construido
--- @param id string
--- @return Vector3 hitboxSize
function Rules.HitboxSize(modelSize: Vector3, id: string): Vector3
	return modelSize * Rules.GetHitboxRatio(id)
end

--- Comprueba que un monstruo cumple el contrato de TAMANO.
---
--- @param id string
--- @return boolean ok
--- @return string? reason
function Rules.AssertDesign(id: string): (boolean, string?)
	local scale = Rules.VisualScale[id]

	if scale == nil then
		-- Un monstruo sin escala declarada usa el valor por defecto, que SI
		-- cumple el diseno. No es un fallo: es un bicho nuevo todavia sin
		-- decidir, y el valor por defecto ya es mayor que el jugador.
		return true, nil
	end

	local range = Rules.Ranges[id]

	if range == nil then
		return true, nil
	end

	if scale < range[1] or scale > range[2] then
		return false, ("escala %.2f fuera del rango %.2f-%.2f"):format(scale, range[1], range[2])
	end

	-- El piso absoluto: por debajo de 1.2 el bicho no se lee como amenaza,
	-- por mucho que su rango declarado lo admita.
	if scale < 1.2 then
		return false, ("escala %.2f menor que el jugador"):format(scale)
	end

	return true, nil
end

--- Comprueba TODOS los monstruos declarados.
---
--- Es lo que ejecuta `MonsterScale.spec`: una sola asercion que recorre la
--- tabla entera, en vez de nueve lineas iguales.
---
--- @return { string } problemas encontrados
function Rules.AuditAll(): { string }
	local problems = {}

	for id in pairs(Rules.VisualScale) do
		local ok, reason = Rules.AssertDesign(id)

		if not ok then
			table.insert(problems, ("%s: %s"):format(tostring(id), tostring(reason)))
		end
	end

	return problems
end

return Rules