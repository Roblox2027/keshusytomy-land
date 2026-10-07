--!strict
--[[
	HazardRules
	MECANICA CARACTERISTICA DE CADA MUNDO (MASTER MISSION V2 - FASE 3).

	POR QUE EXISTE ESTE MODULO
	--------------------------
	Los cinco mundos comparten motor y hasta esta mision se JUGABAN IGUAL:
	cambiar de mundo era cambiar de color. Cada mundo tiene ahora un peligro
	propio que obliga al jugador a reaccionar distinto:

	  Forest:  EMBOSCADA   - entrar en la zona genera enemigos sorpresa.
	  Desert:  ARENAS MOVEDIZAS - el suelo frena al jugador dentro.
	  Ice:     VIENTO      - rachas que empujan al jugador periodicamente.
	  Volcano: LAVA        - dano por segundo dentro de la zona.
	  Cyber:   LASER       - dano por pulsos TELEGRAFIADOS (on/off visible).

	QUE VIVE AQUI Y QUE NO
	----------------------
	Aqui vive el CATALOGO y toda la aritmetica (radios, daños, fases del
	laser, cooldowns de emboscada): es puro y se prueba sin motor. El
	servicio (`HazardService`) aporta las partes, el hilo y la lectura de
	posiciones, que son lo que no se puede probar en local.

	LA REGLA DE SEGURIDAD
	---------------------
	El dano de las zonas lo aplica `CombatService.ApplyDamage`, la UNICA
	autoridad de dano del servidor: pasa por invulnerabilidad, por la ronda
	en curso y por el multiplicador de muerte subita como cualquier bomba.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- TIPOS DE PELIGRO
-- ---------------------------------------------------------------------------

Rules.Kind = {
	Quicksand = "Quicksand",
	Gust = "Gust",
	Lava = "Lava",
	Laser = "Laser",
	Ambush = "Ambush",
}

-- ---------------------------------------------------------------------------
-- CATALOGO POR MUNDO
-- ---------------------------------------------------------------------------
--
-- Un peligro por mundo. `Radius` es el radio de la zona visible; el resto
-- de campos dependen del tipo. Los valores son de PARTIDA: se balancean
-- con las pruebas de gameplay, no con el gusto de quien los escribe.

Rules.ByWorld = {
	Forest = {
		Kind = Rules.Kind.Ambush,
		Radius = 24,
		-- Enemigos de la emboscada: fauna del bosque, no jefes. La
		-- sorpresa la pone el MOMENTO (entrar en la zona), no el bicho.
		Spawns = { "Slime", "Shadow" },
		Count = 2,
		-- Una zona emboscada no puede reactivarse al instante: sin este
		-- enfriamiento, cruzar el claro dos veces llenaria el mapa.
		Cooldown = 90,
	},
	Desert = {
		Kind = Rules.Kind.Quicksand,
		Radius = 22,
		-- Multiplicador de velocidad DENTRO de la zona. 0.5 se lee de
		-- inmediato ("el suelo me traga") sin inmovilizar: inmovilizar
		-- sin aviso es la forma clasica de frustrar a un nino.
		SpeedMultiplier = 0.5,
	},
	Ice = {
		Kind = Rules.Kind.Gust,
		Radius = 26,
		-- Impulso de la racha (studs/s durante el golpe). La direccion la
		-- decide el servicio por zona; aqui vive la magnitud y el ritmo.
		Impulse = 40,
		Interval = 2.5,
	},
	Volcano = {
		Kind = Rules.Kind.Lava,
		Radius = 18,
		-- Dano por segundo dentro de la lava. Con 100 de vida son ~17 s
		-- de margen: castiga quedarse, no cruzar.
		DamagePerSecond = 6,
	},
	Cyber = {
		Kind = Rules.Kind.Laser,
		Radius = 16,
		-- Dano por pulso y TELEGRAPH: el laser esta encendido `OnTime`
		-- segundos y apagado `OffTime`. La ventana apagada ES la mecanica:
		-- cruzar en verde es gratis, cruzar en rojo cuesta vida.
		DamagePerPulse = 14,
		OnTime = 2.5,
		OffTime = 3.5,
	},
}

-- ---------------------------------------------------------------------------
-- LIMITES Y RITMO
-- ---------------------------------------------------------------------------

--- Zonas de peligro por mundo.
---
--- Cuatro bastan para que la mecanica se ENCUENTRE sin convertir el mapa en
--- un campo de minas: el mundo sigue siendo de exploracion con zonas
--- peligrosas, no un pasillo de dano continuo.
Rules.MaxZonesPerWorld = 4

--- Segundos entre pasos del servicio.
---
--- Medio segundo es suficiente para un DOT legible y un laser telegrafiado,
--- y cuesta una fraccion de frame: doce zonas por cinco mundos son menos de
--- sesenta comprobaciones de distancia por paso.
Rules.TickSeconds = 0.5

--- Velocidad de caminar por defecto del jugador.
---
--- La arenas movedizas la pisan y la DEVUELVEN al salir. La constante vive
--- aqui y no en "lo que tuviera el jugador antes" porque los powerups de
--- velocidad tambien la tocan: restaurar "lo anterior" guardado pisaria un
--- powerup recogido dentro de la zona.
Rules.DefaultWalkSpeed = 16

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

--- Peligro de un mundo, o nil si el mundo no existe.
--- @param worldId any
--- @return any?
function Rules.ForWorld(worldId: any): any?
	if type(worldId) ~= "string" then
		return nil
	end

	return Rules.ByWorld[worldId]
end

--- Mundos con peligro, en orden estable (diagnostico y pruebas).
--- @return { string }
function Rules.GetWorldIds(): { string }
	local out = {}

	for worldId in pairs(Rules.ByWorld) do
		table.insert(out, worldId)
	end

	table.sort(out)
	return out
end

-- ---------------------------------------------------------------------------
-- ARITMETICA
-- ---------------------------------------------------------------------------

--- El laser esta ENCENDIDO en este instante.
---
--- La fase se deriva del reloj y no de un contador del servicio: dos
--- servidores con el mismo reloj ven la misma fase, y un laser nunca se
--- queda encendido porque un tick se perdio.
--- @param hazard any definicion de `ForWorld` (Kind = Laser)
--- @param now any reloj del servidor
--- @return boolean
function Rules.IsLaserOn(hazard: any, now: any): boolean
	if type(hazard) ~= "table" or hazard.Kind ~= Rules.Kind.Laser then
		return false
	end

	local t = tonumber(now)

	if not t or t ~= t then
		return false
	end

	local cycle = (tonumber(hazard.OnTime) or 0) + (tonumber(hazard.OffTime) or 0)

	if cycle <= 0 then
		return false
	end

	return (t % cycle) < (tonumber(hazard.OnTime) or 0)
end

--- Dano que aplica una zona en UN paso del servicio.
---
--- Lava: proporcional al paso (dps * dt). Laser: el pulso entero, solo si
--- esta encendido. El resto de peligros no hacen dano directo: su efecto
--- es de movimiento o de aparicion.
--- @param hazard any
--- @param now any
--- @param tickSeconds any
--- @return number dano del paso (0 = este paso no daña)
function Rules.DamagePerTick(hazard: any, now: any, tickSeconds: any): number
	if type(hazard) ~= "table" then
		return 0
	end

	local dt = tonumber(tickSeconds) or Rules.TickSeconds

	if hazard.Kind == Rules.Kind.Lava then
		return (tonumber(hazard.DamagePerSecond) or 0) * dt
	end

	if hazard.Kind == Rules.Kind.Laser then
		if Rules.IsLaserOn(hazard, now) then
			-- El pulso se prorratea al paso: con el tick a 0.5 s y el laser
			-- encendido 2.5 s, el jugador recibe el pulso completo si se
			-- queda dentro toda la ventana.
			return (tonumber(hazard.DamagePerPulse) or 0)
				* (dt / math.max(tonumber(hazard.OnTime) or 1, dt))
		end

		return 0
	end

	return 0
end

--- Una emboscada puede dispararse AHORA.
--- @param lastFiredAt any instante del ultimo disparo (nil = nunca)
--- @param cooldown any
--- @param now any
--- @return boolean
function Rules.CanAmbush(lastFiredAt: any, cooldown: any, now: any): boolean
	local t = tonumber(now)

	if not t or t ~= t then
		return false
	end

	local last = tonumber(lastFiredAt)

	if not last then
		return true
	end

	return (t - last) >= (tonumber(cooldown) or 0)
end

--- Velocidad que aplica la arena movediza.
--- @param hazard any
--- @return number
function Rules.SlowedWalkSpeed(hazard: any): number
	if type(hazard) ~= "table" or hazard.Kind ~= Rules.Kind.Quicksand then
		return Rules.DefaultWalkSpeed
	end

	local mult = tonumber(hazard.SpeedMultiplier) or 1
	return math.max(1, Rules.DefaultWalkSpeed * mult)
end

return Rules
