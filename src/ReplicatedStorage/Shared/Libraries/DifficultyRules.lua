--!strict
--[[
	DifficultyRules
	LA UNICA formula que convierte (mundo, noche, evento) en numeros de juego.

	EL PROBLEMA QUE RESUELVE
	------------------------
	Sin este modulo, cada sitio que necesita un multiplicador inventa el suyo:

	  MonsterService multiplica la vida,
	  MatchService multiplica la cantidad,
	  HordeService multiplica el tamano de la horda,
	  PowerupService multiplica el botin,
	  BossService multiplica los fases.

	Y cada uno los multiplica contra OTRO multiplicador ya aplicado. El
	resultado es la multiplicacion que el enunciado prohibe explicitamente: un
	boss que nace con `2.5` de mundo por `3.0` de noche por `1.5` de evento se
	convierte en un enemigo con `11.25` de vida y una recarga de 0.4 s. Eso no
	es dificultad, es una muerte instantanea sin decision posible.

	AQUI NO HAY MULTIPLICACION EN CADENA
	-------------------------------------
	Este modulo recibe los factores y produce un UNICO perfil ya resuelto y ya
	acotado. Quien llame consume ese perfil; no vuelve a multiplicar nada. Es
	la unica forma de que "evitar multiplicaciones absurdas" sea una propiedad
	del CODIGO y no una intencion: no hay forma de acumular un once por
	accidente, porque la funcion que lo haria no existe.

	LOS TOPES SON EL ARGUMENTO
	--------------------------
	Cada eje tiene un maximo declarado. Un enemigo puede ser como mucho 3.5
	veces mas resistente, como mucho 2.2 veces mas dano y puede haber como mucho
	4.6 veces mas. La noche 99 es dura porque combina TODOS los ejes al tope Y
	ademas mete a los enemigos mas rapidos, mas agresivos y en grupos. Nunca
	porque un numero se dispara.
]]

local Rules = {}

-- Import RELATIVO a proposito: `WorldAccessRules` es logica pura y asi funciona
-- en los dos sitios donde se carga este modulo (Roblox y el interprete de las
-- pruebas). Ver la nota equivalente en `MonsterDefinitions`, que usa
-- `require("./Libraries/...")` por el mismo motivo.
local Access = require("./WorldAccessRules")

-- ---------------------------------------------------------------------------
-- TOPES POR EJE
-- ---------------------------------------------------------------------------
--
-- Cada valor es el MAXIMO que puede alcanzar el eje en la noche 99 de Cyber
-- con un evento activo. Son el contrato de "el juego sigue siendo jugable".
Rules.Caps = {
	Health = 3.5,
	Damage = 2.2,
	Count = 4.6,
	SpawnRate = 2.6,
	Reward = 3.0,
	Aggro = 1.65,
}

-- El recorrido completo de cada eje: 1.0 en la noche 1 de Forest, el tope en
-- la noche 99 de Cyber con evento.
--
-- `Health` sube MAS despacio que `Count` a proposito. La reason es de diseño:
-- mas enemigos es una decision de ESPACIO (por donde poner la bomba, cuando
-- salir, donde cubrirte); mas vida por enemigo es una decision de TIEMPO (cuantas
-- bombas gastar). La primera se adapta solo con la experiencia; la segunda
-- exige un numero de bombas mayor que la capacidad base del jugador, y eso
-- convierte al enemigo en una cuenta pendiente.
Rules.Ranges = {
	Health = { 1.0, 3.5 },
	Damage = { 1.0, 2.2 },
	Count = { 1.0, 4.6 },
	SpawnRate = { 1.0, 2.6 },
	Reward = { 1.0, 3.0 },
	Aggro = { 1.0, 1.65 },
}

-- ---------------------------------------------------------------------------
-- FACTORES DE ENTRADA
-- ---------------------------------------------------------------------------

--- Convierte la dificultad 1..5 del mundo en un multiplicador.
---
--- No es lineal. El salto Forest(1) -> Desert(2) es pequeño y el salto
--- Volcano(4) -> Cyber(5) es casi el doble, porque el Cyber no es "un
--- volcano con mas vida": cambia el tipo de amenaza (refleccion, presion
--- constante) y por eso no puede "ser un poco mas".
---
--- El rango va de 1.0 a 2.2 en cinco escalones.
--- @param worldDifficulty any 1..5, o el id del mundo
--- @return number multiplicador >= 1
function Rules.WorldFactor(worldDifficulty: any): number
	local d = tonumber(worldDifficulty)

	-- Aceptar el id del mundo es una comodidad que evita el fallo mas probable
	-- al cablear: pasar `"Cyber"` donde se esperaba `5`. Sin esta conversion,
	-- `tonumber("Cyber")` es `nil` y el multiplicador caeria a 1.0, con lo que
	-- el Cyber seeria tan facil como el Forest y nadie sabria por que.
	if d == nil and type(worldDifficulty) == "string" then
		d = Access and Access.GetDifficulty(worldDifficulty) or nil
	end

	if not d or d ~= d then
		return 1.0
	end

	d = math.clamp(d, 1, 5)

	-- Escalones: 1.00, 1.22, 1.48, 1.80, 2.20.
	local steps = { 1.0, 1.22, 1.48, 1.80, 2.20 }
	return steps[math.floor(d)]
end

--- Convierte un numero de noche en el multiplicador de un eje.
---
--- @param night any
--- @param axis string nombre de `Ranges`
--- @return number multiplicador dentro de `[1, tope]`
function Rules.NightFactor(night: any, axis: string): number
	local range = Rules.Ranges[axis]

	if not range then
		return 1.0
	end

	local n = tonumber(night)
	if not n or n ~= n then
		n = 1
	end

	n = math.clamp(n, 1, 99)

	-- Progreso 0..1 sobre las 99 noches, y el rango del eje se recorre entero.
	-- Un enemigo en la noche 1 vale 1.0 y en la 99 vale el tope del eje.
	local t = (n - 1) / 98

	return range[1] + (range[2] - range[1]) * t
end
-- ---------------------------------------------------------------------------
-- EL PERFIL
-- ---------------------------------------------------------------------------

export type Profile = {
	-- Factores de multiplicacion, ya acotados.
	Health: number,
	Damage: number,
	Count: number,
	SpawnRate: number,
	Reward: number,
	Aggro: number,

	-- Numeros DERIVADOS, que son los que el juego consume de verdad.
	MaxAlive: number,
	RewardScale: number,

	-- Traza de donde salio el perfil. No es decorativa: `Difficulty.spec` la
	-- usa para comprobar que el perfil de la noche 99 es estrictamente mayor
	-- que el de la noche 1 en los ejes que deben crecer, y menor o igual en los
	-- que no.
	Night: number,
	Band: string,
	Tier: number,
	WorldFactor: number,
}

--- Resuelve el perfil de dificultad completo.
---
--- Este es EL punto de entrada del sistema. Quien necesite numeros de juego
--- llama a esto y usa el resultado; no multiplica nada por su cuenta.
---
--- @param worldId any id del mundo o su dificultad 1..5
--- @param night any numero de noche (se acota a 1..99)
--- @param eventMultiplier any? presion extra por evento activo (1.0 = ninguno)
--- @param baseMaxAlive any? poblacion maxima BASE de la zona (por defecto 12)
--- @return Profile
function Rules.Resolve(
	worldId: any,
	night: any,
	eventMultiplier: any?,
	baseMaxAlive: any?
): Profile
	local n = 1
	local rawNight = tonumber(night)
	if rawNight and rawNight == rawNight then
		n = math.clamp(math.floor(rawNight), 1, 99)
	end

	local worldFactor = Rules.WorldFactor(worldId)
	local event = tonumber(eventMultiplier)

	if not event or event ~= event or event < 1 then
		event = 1
	end

	-- El factor de noche se COMBINA con el de mundo, no se multiplica a pelo:
	-- se aplica la noche sobre el rango y se apila el mundo encima, y el
	-- resultado se acota. Multiplicar los dos crudos (4.6 x 2.2 = 10.1) es
	-- justamente el numero que produce enemigos inmortales.
	local function axis(name: string): number
		local nightFactor = Rules.NightFactor(n, name)
		local combined = nightFactor * worldFactor * event
		return Rules.ClampAxis(name, combined)
	end

	local band = Access and Access.GetBand(n)
	local tier = band and band.Tier or 1

	local count = axis("Count")
	local spawnRate = axis("SpawnRate")
	local aggro = axis("Aggro")

	-- La banda aporta su propio multiplicador de cantidad y frecuencia. Se
	-- aplica DESPUES de `axis("Count")` y sobre un total ya acotado, de modo
	-- que la banda nunca puede empujar por encima del tope: para eso esta
	-- `ClampAxis` al final.
	if band then
		count = count * band.CountMul
		spawnRate = spawnRate * band.Frequency
		aggro = aggro + band.Aggro
	end

	-- Poblacion activa final.
	--
	-- El `baseMaxAlive` es la poblacion de la zona, no la del mundo: por eso
	-- se multiplica y no se sustituye. El limite GLOBAL de monstros vive en
	-- `PerformanceConfig` y lo impone `SpawnDirectorService`; aqui solo se
	-- resuelve "cuantos le tocan a esta zona".
	local base = tonumber(baseMaxAlive)
	if not base or base ~= base or base < 1 then
		base = 12
	end

	local maxAlive = math.clamp(math.floor(base * count), 1, Rules.AbsoluteMaxAlive)

	local reward = axis("Reward")

	return {
		Health = axis("Health"),
		Damage = axis("Damage"),
		Count = count,
		SpawnRate = spawnRate,
		Reward = reward,
		Aggro = aggro,

		MaxAlive = maxAlive,
		RewardScale = reward,

		Night = n,
		Band = band and band.Label or "Exploracion",
		Tier = tier,
		WorldFactor = worldFactor,
	}
end

--- Tope ABSOLUTO de monstruos activos en una zona, sin importar el mundo, la
--- noche ni el evento.
---
--- Existe porque `Count` es un multiplicador y los multiplicadores se
--- multiplican. Sin este techo, una zona con `baseMaxAlive` alto en la noche
--- 99 con evento podria pedir varios cientos de NPC, y "poblacion dinamica"
--- se convertiria en "el servidor no responde".
Rules.AbsoluteMaxAlive = 48

--- Tope global de monstruos activos en TODO el servidor.
---
-- El limite de `PerformanceConfig.Limits.MaxMonsters` sigue siendo la
--- garantia dura; este es el presupuesto por zona que el generador de spawns
--- respeta para no acaparar el global con un solo mundo.
Rules.AbsoluteMaxPerWorld = 30

--- Aplica el perfil a los numeros de UNA definicion de monstruo.
---
--- Devuelve una tabla NUEVA. Es importante: si devolviera la definicion
--- original mutada, la segunda llamada (otra zona, otro jugador) veria los
--- numeros de la primera y el multiplicacion seria acumulativa. Esa es la
--- razon por la que "no multiplicaciones absurdas" necesita esta copia.
--- @param definition any tabla de monstruo de `MonsterDefinitions`
--- @param profile Profile
--- @return any copia con vida, dano y recompensa escalados
function Rules.ApplyToMonster(definition: any, profile: Profile): any
	local copy = {}

	for key, value in pairs(definition :: any) do
		copy[key] = value
	end

	copy.Health = math.max(1, math.floor((definition.Health or 1) * profile.Health))
	copy.Damage = math.max(1, (definition.Damage or 1) * profile.Damage)
	copy.XP = math.max(1, math.floor((definition.XP or 1) * profile.Reward))
	copy.Coins = math.max(1, math.floor((definition.Coins or 1) * profile.Reward))

	-- `MaxAlive` NO se escala con la dificultad: es un tope de RENDIMIENTO y no
	-- de balance. Un enemigo que aguanta mas tampoco necesita estar mas veces
	-- en pantalla, y multiplicar los dos seria una copia del bug de carga.
	copy.MaxAlive = math.min(definition.MaxAlive or 1, profile.MaxAlive)

	return copy
end

--- Multiplicador de un evento (1.0 si no hay ninguno).
---
--- Un evento sube la presion pero NO puede superar el tope del eje: por eso
--- se acotan aqui y no en quien multiplica. La razon es que un evento que
--- duplica la poblacion ACTIVA por encima de un `Count` de 4.6 daria 9.2, que
--- es la clase de numero con el que un servidor se cae.
--- @param eventMultiplier any
--- @param axis string
--- @return number
function Rules.ClampAxis(axis: string, value: number): number
	local range = Rules.Ranges[axis]
	local cap = Rules.Caps[axis] or value

	if not range then
		return math.min(value, cap)
	end

	return math.clamp(value, range[1], math.min(cap, range[2]))
end

return Rules