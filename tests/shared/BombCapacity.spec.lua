--!strict
--[[
	BombCapacity.spec
	PRUEBAS DE REGRESION DE LOS DOS P0 DE LA BOMBA.

	QUE CUBRE ESTE ARCHIVO
	---------------------
	Los dos fallos que hicieron que "la bomba no aparece" y "solo puedo poner
	una" fueron fallos de CONFIGURACION y de CONTRATO, no de logica de combate.
	Eso significa que ninguna prueba de las que existian los podia ver:
	`BombButton.spec` comprueba la FORMA del boton y `Gameplay.spec` la curva de
	dano. Ninguna mira quien decide si la bomba sale.

	1. CAPACIDAD (P0: "solo puedo colocar una bomba")
	   `GameConfig.BombCapacity` tiene que valer al menos 2. Con 1 el jugador
	   no puede tener dos bombas vivas ni aunque el enfriamiento y la mecha lo
	   permitan, y la bomba deja de ser una herramienta tactica.

	2. ESTADOS JUGABLES (P0: "la bomba no aparece")
	   `AntiExploitRules` exige que la ronda este en una lista de estados. La
	   ronda tiene VARIOS estados jugables, no uno: si el filtro declara solo
	   `Playing`, la bomba se apaga sola en `SuddenDeath` sin avisar.

	Estas pruebas se escriben DESPUES de medir el fallo en PLAY, y cada una
	 dice que fallo atraparia si alguien revirtiera el arreglo.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local PerformanceConfig = require("../../src/ReplicatedStorage/Shared/Config/PerformanceConfig")
local AntiExploitRules = require("../../src/ReplicatedStorage/Shared/Libraries/AntiExploitRules")

local function describeBombCapacity()
	Harness.describe("GameConfig: la capacidad de bombas", function()
		Harness.it("permite al menos DOS bombas vivas a la vez", function()
			-- MEDIDO EN PLAY: el sintoma reportado era "solo puedo colocar una
			-- bomba". Aunque la causa principal era un cerrojo del cliente,
			-- la capacidad de DISENO tambien decia 1 en una version temprana.
			-- Con 1 no hay decision tactica: se coloca o no se coloca.
			expect.toBe(GameConfig.BombCapacity >= 2, true)
		end)

		Harness.it("el enfriamiento deja colocar la segunda antes de que estalle la primera", function()
			-- La capacidad solo es REAL si se puede alcanzar:
			--
			--   A -> t=0
			--   B -> t=BombCooldown   (ha pasado el enfriamiento)
			--   A explota -> t=BombCooldown + mecha
			--
			-- Si el enfriamiento fuera mayor que la mecha, nunca se podrian
			-- tener dos a la vez y la capacidad seria decorativa.
			expect.toBe(GameConfig.BombCooldown < GameConfig.DefaultBombFuseTime, true)
		end)

		Harness.it("la capacidad base no supera el tope de rendimiento", function()
			-- Son dos limites DISTINTOS: la capacidad es balance y el tope es
			-- seguridad. Si la primera supera al segundo, el filtro de
			-- rendimiento puede rechazar una bomba que el jugador tenia
			-- derecho a poner.
			expect.toBe(
				GameConfig.BombCapacity <= PerformanceConfig.Limits.MaxBombsPerPlayer,
				true
			)
		end)

		Harness.it("la capacidad es un numero entero positivo", function()
			-- Un 0 o un negativo haria imposible colocar bombas, y un decimal
			-- haria que la cuenta de bombas vivas nunca cuadrase con el limite.
			expect.toBe(GameConfig.BombCapacity >= 1, true)
			expect.toBe(GameConfig.BombCapacity % 1, 0)
		end)
	end)
	-- ---------------------------------------------------------------------
	-- ESTADOS JUGABLES
	-- ---------------------------------------------------------------------
	Harness.describe("AntiExploitRules: los estados en los que se puede colocar una bomba", function()
		local place = AntiExploitRules.Channels.BombAction.Place

		Harness.it("el canal declara una lista de estados, no uno solo", function()
			-- MEDIDO EN PLAY: el canal declaraba `state = "Playing"` y el log
			-- decia
			--
			--   AntiExploitService: ... BombAction.Place -> state_violation (malicious)
			--
			-- durante toda la ronda de muerte subita. Un unico estado es una
			-- suposicion sobre una maquina de estados que tiene varios.
			expect.toBe(place.allowedStates ~= nil, true)
		end)

		Harness.it("la bomba se acepta en Playing", function()
			local allowed = AntiExploitRules.Check("BombAction", "Place", {
				serverState = "Playing",
				distance = 5,
				maxDistance = GameConfig.BombPlacementRange,
			})
			expect.toBe(allowed, true)
		end)

		Harness.it("la bomba se acepta en SuddenDeath", function()
			-- `SuddenDeath` es tan jugable como `Playing`: el reloj corre, el
			-- multiplicador de dano esta activo y los monstruos siguen
			-- atacando. Excluirlo deja al jugador sin su unica herramienta
			-- justo en la parte final de la ronda, que es donde mas la usa.
			local allowed = AntiExploitRules.Check("BombAction", "Place", {
				serverState = "SuddenDeath",
				distance = 5,
				maxDistance = GameConfig.BombPlacementRange,
			})
			expect.toBe(allowed, true)
		end)

		Harness.it("la bomba se RECHAZA en el lobby", function()
			-- El filtro tiene que seguir funcionando. Un filtro que acepta en
			-- cualquier estado no es un filtro.
			local allowed, reason = AntiExploitRules.Check("BombAction", "Place", {
				serverState = "Lobby",
				distance = 5,
				maxDistance = GameConfig.BombPlacementRange,
			})
			expect.toBe(allowed, false)
			expect.toBe(reason, AntiExploitRules.Reason.StateViolation)
		end)

		Harness.it("un estado fuera de ronda cuenta como SOSPECHOSO, no como MALICIOSO", function()
			-- MEDIDO: entrar en la ronda por la puerta equivocada es un patron
			-- de juego, no un ataque. Marcarlo `malicious` sumaba una senal de
			-- EXPELIDO a un jugador que solo estaba jugando, y el filtro de red
			-- es el unico sitio del proyecto que puede echar a alguien.
			local _, _, severity = AntiExploitRules.Check("BombAction", "Place", {
				serverState = "Waiting",
				distance = 5,
				maxDistance = GameConfig.BombPlacementRange,
			})
			expect.toBe(severity, AntiExploitRules.Severity.Suspicious)
		end)

		Harness.it("la distancia la sigue midiendo el servidor", function()
			-- La correccion del estado NO puede aflojar la distancia: son dos
			-- comprobaciones distintas y las dos importan.
			local allowed, reason = AntiExploitRules.Check("BombAction", "Place", {
				serverState = "Playing",
				distance = 9999,
				maxDistance = GameConfig.BombPlacementRange,
			})
			expect.toBe(allowed, false)
			expect.toBe(reason, AntiExploitRules.Reason.DistanceViolation)
		end)
	end)
end

return describeBombCapacity
