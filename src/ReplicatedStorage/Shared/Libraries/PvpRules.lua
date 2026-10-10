--!strict
--[[
	PvpRules
	Aritmetica del modo PvP de la arena del lobby (sin motor, probada en local).

	POR QUE EXISTE
	--------------
	La arena PvP del lobby ya estaba construida (muros, marcadores `PvPSpawn_A`,
	`PvPSpawn_B`, `PvPCenter`, `PvPEntry`) pero ningun servicio la leia: eran
	paredes bonitas sin funcion. Este modulo reunе la logica que Decide dos
	cosas y las deja puras para poder probarlas sin abrir Studio:

	  - ASSIGNTEAM: a que equipo entra un jugador, de forma que los bandos
	    queden equilibrados. Un PvP con 5 contra 1 no es un duelo, es una
	    emboscada, y el jugador nuevo lo lee como "aqui no puedo ganar".
	  - ISINSIDEARENA / ISNEAR: si una posicion cae dentro de la caja de la
	    arena o cerca de un marcador. El servicio las usa para saber cuando
	    alguien entra (y se le asigna equipo) y cuando sale (y se le retira
	    el modo PvP, que es lo que apaga el dano en el lobby).

	LA REGLA DE AUTORIDAD
	---------------------
	Esto no aplica dano ni mueve a nadie: solo CALCULA. Quien decide de verdad
	es el servidor (`CombatService.ApplyDamage` y `PvpService`), que consume
	estas funciones. El cliente no participa.
]]

local Rules = {}

--- Equipos del modo PvP. Dos, para que el duelo sea simetrico.
Rules.Teams = { "A", "B" }

--- Equipo al que entra un jugador nuevo, dados los tamanos actuales.
---
--- Regla de equilibrio: va al bando con MENOS gente. Si estan iguales (o si
--- la cuenta es invalida), entra al A, que es una decision determinista y no
--- un capricho: sin regla fija en el empate, dos servidores balancearian
--- distinto el mismo estado y el comportamiento dejaria de ser reproducible.
--- @param countA any jugadores en el equipo A
--- @param countB any jugadores en el equipo B
--- @return string "A" | "B"
function Rules.AssignTeam(countA: any, countB: any): string
	local a = tonumber(countA) or 0
	local b = tonumber(countB) or 0

	if b < a then
		return "B"
	end

	return "A"
end

--- Fuego amigo: ¿el origen y el objetivo son del MISMO equipo PvP?
---
--- EL HUECO QUE CIERRA
--- -------------------
--- `PvpService` reparte a los jugadores en dos bandos (A/B) y los coloca en
--- lados opuestos de la arena, pero el dano se aplicaba con SOLO mirar
--- `PvpActive`: dos companeros de equipo se podian matar entre si (y con
--- bombas), que convierte el duelo por equipos en una pelea a todos contra
--- todos. Esta funcion es la REGLA que falta; el servicio
--- (`CombatService.ApplyDamage`) es quien la consume.
---
--- Es PURA a proposito: solo compara dos etiquetas de equipo. Sin equipo en
--- uno de los dos (nil, que es el caso de quien aun no entro o ya salio) NO
--- hay fuego amigo que aplicar: la decision de si se puede danar la toma
--- `ApplyDamage` con las reglas de PvP/ronda, no aqui.
--- @param sourceTeam any equipo del atacante (atributo `PvpTeam`)
--- @param targetTeam any equipo de la victima (atributo `PvpTeam`)
--- @return boolean true si ambos son del mismo equipo conocido
function Rules.IsFriendlyFire(sourceTeam: any, targetTeam: any): boolean
	if type(sourceTeam) ~= "string" or type(targetTeam) ~= "string" then
		return false
	end

	-- Equipo vacio no es un equipo: quien no tiene bando no puede ser aliado.
	if sourceTeam == "" or targetTeam == "" then
		return false
	end

	return sourceTeam == targetTeam
end

--- La posicion cae dentro de la caja de la arena (plano XZ).
---
--- Va por campos (`.X`, `.Z`) a proposito, igual que `CombatRules.InArc`: asi
--- vale para un `Vector3` del motor y para una tabla `{X, Z}` de prueba sin
--- depender de la API del motor.
--- @param pos any posicion a comprobar (`.X`/`.Z`)
--- @param center any centro de la arena (`.X`/`.Z`)
--- @param half any semitamano de la caja (`.X`/`.`.Z`, es decir, la MITAD)
--- @return boolean
function Rules.IsInsideArena(pos: any, center: any, half: any): boolean
	local hx = tonumber(half.X) or 0
	local hz = tonumber(half.Z) or 0

	return math.abs((tonumber(pos.X) or 0) - (tonumber(center.X) or 0)) <= hx
		and math.abs((tonumber(pos.Z) or 0) - (tonumber(center.Z) or 0)) <= hz
end

--- La posicion esta a menos de `radius` del objetivo (plano XZ).
---
--- Es la prueba de "ha pisado el marcador de entrada". Se mide en XZ, no en 3D,
--- porque el marcador y el suelo estan a la misma altura: una componente Y no
--- anadiria informacion y si podria descartar a un jugador en una rampa.
--- @param pos any
--- @param target any
--- @param radius number
--- @return boolean
function Rules.IsNear(pos: any, target: any, radius: number): boolean
	local dx = (tonumber(pos.X) or 0) - (tonumber(target.X) or 0)
	local dz = (tonumber(pos.Z) or 0) - (tonumber(target.Z) or 0)
	local r = tonumber(radius) or 0

	-- Al cuadrado para evitar la raiz. `radius` negativo se trata como 0: una
	-- orden mal formada no debe atraer a todo el mapa.
	if r < 0 then
		r = 0
	end

	return (dx * dx + dz * dz) <= (r * r)
end

--- Formatea el marcador de kills a partir de una lista de entradas.
---
--- Va por CAMPOS y es pura a proposito: el marcador es lo que convierte la
--- arena en una COMPETICIA (ver quién va ganando es la razon de volver a
--- entrar), y esa decision de "a quien muestro y en que orden" se puede probar
--- sin motor. El servicio solo le pasa los datos y pinta el texto.
---
--- Reglas: solo se listan jugadores con al menos una kill; se ordenan por
--- kills desc y, a igualdad, por nombre (determinista); se acotan a `Limit`
--- filas para que el cartel quepa en pantalla.
--- @param entries any lista de `{ Name, Kills, Team }`
--- @param limit number? tope de filas (por defecto 5)
--- @return string
function Rules.FormatScoreboard(entries: any, limit: number?): string
	local list: { { Name: string, Kills: number } } = {}

	if type(entries) == "table" then
		for _, entry in ipairs(entries) do
			if type(entry) == "table" then
				local kills = tonumber(entry.Kills) or 0

				if kills > 0 then
					table.insert(list, {
						Name = tostring(entry.Name or "?"),
						Kills = kills,
					})
				end
			end
		end
	end

	if #list == 0 then
		return "Sin kills aun"
	end

	table.sort(list, function(a, b)
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		end
		return a.Name < b.Name
	end)

	local medals = { "1.", "2.", "3.", "4.", "5." }
	local cap = math.clamp(tonumber(limit) or 5, 1, #medals)
	local lines: { string } = {}

	for index = 1, math.min(#list, cap) do
		local entry = list[index]
		table.insert(lines, ("%s %s  [%d]"):format(medals[index], entry.Name, entry.Kills))
	end

	return table.concat(lines, "\n")
end

--- Formatea una linea de killfeed: quien elimino a quien.
---
--- Es pura por el mismo motivo que el marcador: el texto exacto es una
--- decision de diseno ("X elimino a Y" frente a "X > Y") y se congela aqui.
--- @param killerName any
--- @param victimName any
--- @return string
function Rules.FormatKillLine(killerName: any, victimName: any): string
	return ("%s  elimino a  %s"):format(
		tostring(killerName or "?"),
		tostring(victimName or "?")
	)
end

return Rules
