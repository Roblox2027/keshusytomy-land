--!strict
--[[
	WorldBounds.spec
	Pruebas del LIMITE LOGICO del mundo.

	POR QUE EXISTE
	--------------
	El P0 de este turno prohibe dos cosas que el codigo hacia: una CAJA alrededor
	del mapa (264-272 muros `Border_Wall_*` por mundo) y un RESCATE que
	teletransportaba al jugador de vuelta al spawn cuando caia. Las dos cosas
	tenian su regla en un servicio con Workspace, y sin regla PURA no habia forma
	de probarlas sin abrir Roblox Studio.

	`WorldBoundsRules` es esa regla: clasifica un punto en `Playable`, `Margin` u
	`OutOfBounds`. No teletransporta, no mata y no toca el juego.

	LO QUE ESTAS PRUEBAS PROTEGEN
	-----------------------------
	1. Que el margen exista y sea grande. Sin margen, el limite es una trampa en
	   el ultimo paso del terreno, que es un muro invisible con otro nombre.
	2. Que cruzar el limite NO sea mortal al instante. Si lo fuera, el jugador no
	   puede explorar el borde, que es justo lo que se le pide.
	3. Que el margen de la especificacion (el mundo mide 466x466 y el terreno
	   jugable 420-440) sea de sobra para el sitio que ocupa el vacio.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Bounds = require("../../src/ReplicatedStorage/Shared/Libraries/WorldBoundsRules")
local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")

-- Caja de un mundo tipico: 466x466 de mundo con el terreno dentro.
local TERRAIN = { minX = -233, maxX = 233, minZ = -233, maxZ = 233 }
local BOUNDS = Bounds.WithMargin(TERRAIN)

-- Caja LOGICA de un mundo: el terreno MAS el margen. El limite que decide si el
-- jugador se ha salido es ESTA caja, no el terreno.
--
-- Para comprobar los estados intermedios hace falta tambien la caja DEL
-- TERRENO (margen 0): es la linea a partir de la cual se empieza a estar fuera
-- del suelo pero todavia dentro de la tolerancia.
local TIGHT = Bounds.WithMargin(TERRAIN, 0)

local function describeWorldBounds()
	Harness.describe("Margen de seguridad", function()
		Harness.it("el margen por defecto es holgado", function()
			-- 90 studs a 16 studs por segundo son casi 6 segundos andando fuera
			-- antes de que el limite diga nada. Menos que eso y el jugador no
			-- tiene tiempo ni de ver que se ha salido.
			expect.toBe(Bounds.Margin >= 60, true)
			expect.toBe(Bounds.RequiredMargin(GameConfig.DefaultPlayerSpeed, 3) <= Bounds.Margin, true)
		end)

		Harness.it("el margen se aplica a los cuatro lados", function()
			expect.toBe(BOUNDS.minX < TERRAIN.minX, true)
			expect.toBe(BOUNDS.maxX > TERRAIN.maxX, true)
			expect.toBe(BOUNDS.minZ < TERRAIN.minZ, true)
			expect.toBe(BOUNDS.maxZ > TERRAIN.maxZ, true)
		end)

		Harness.it("un margen explicito pisa al de por defecto", function()
			local tight = Bounds.WithMargin(TERRAIN, 10)
			expect.toBe(tight.minX, TERRAIN.minX - 10)
			expect.toBe(tight.maxZ, TERRAIN.maxZ + 10)
		end)
	end)

	Harness.describe("Clasificacion de un punto", function()
		Harness.it("el centro del mundo es jugable", function()
			expect.toBe(Bounds.Classify(BOUNDS, { x = 0, z = 0 }), Bounds.Zone.Playable)
		end)

		Harness.it("el ultimo metro de terreno sigue siendo jugable", function()
			-- El terreno llega justo al limite de la caja: el jugador tiene que
			-- poder pisar el ultimo metro sin nada que le pase.
			expect.toBe(Bounds.Classify(TIGHT, { x = TERRAIN.maxX, z = 0 }), Bounds.Zone.Playable)
		end)

		Harness.it("justo fuera del terreno sigue siendo zona de juego", function()
			-- Diez studs mas alla del ultimo suelo el jugador sigue dentro de la
			-- caja LOGICA (terreno + margen). Puede salirse del terreno y volver
			-- andando: eso es lo que distingue una red de seguridad de un muro.
			local p = { x = TERRAIN.maxX + 10, z = 0 }
			expect.toBe(Bounds.Classify(BOUNDS, p), Bounds.Zone.Playable)
			expect.toBe(Bounds.IsOutOfBounds(BOUNDS, p), false)
		end)

		Harness.it("pasado el margen se sale del mundo", function()
			local far = TERRAIN.maxX + Bounds.Margin + 10
			expect.toBe(Bounds.Classify(BOUNDS, { x = far, z = 0 }), Bounds.Zone.OutOfBounds)
			expect.toBe(Bounds.IsOutOfBounds(BOUNDS, { x = far, z = 0 }), true)
		end)

		Harness.it("la cota de salida se comprueba en los dos ejes", function()
			local far = TERRAIN.minZ - Bounds.Margin - 10
			expect.toBe(Bounds.IsOutOfBounds(BOUNDS, { x = 0, z = far }), true)
			expect.toBe(Bounds.IsOutOfBounds(BOUNDS, { x = -far, z = 0 }), true)
		end)

		Harness.it("la altura no_limits el limite", function()
			-- Un jugador puede estar 200 studs por encima del mundo (un salto o
			-- una explosion) y sigue estando en el mismo sitio en el plano. La
			-- altura la decide `FallDeathY`, no el limite del mapa.
			local p = { x = 0, y = 500, z = 0 }
			expect.toBe(Bounds.Classify(BOUNDS, p), Bounds.Zone.Playable)
		end)
	end)

	Harness.describe("Lo que el limite NO hace", function()
		Harness.it("no exporta ninguna accion sobre el jugador", function()
			-- El limite es una red, no un muro ni un teletransporte. Si este
			-- modulo tuviera una funcion que moviera al jugador, la caida habria
			-- vuelto a ser un rescate con otro nombre.
			--
			-- Se recorre con `pairs` y se compara el NOMBRE en una tabla aparte.
			-- Leer `Bounds.Teleport` directamente no vale: el analizador da por
			-- hecho que la clave existe, y "comprobar que no existe" es
			-- justamente lo que no se puede expresar con un acceso literal.
			local forbidden = {
				Teleport = true,
				Pivot = true,
				Kill = true,
				Move = true,
				Set = true,
				Rescue = true,
			}
			for name in pairs(Bounds) do
				expect.toBe(forbidden[name], nil)
			end
		end)

		Harness.it("la tolerancia solo ensancha el limite", function()
			-- El estado `Margin` es la banda de TOLERANCIA alrededor de la caja
			-- logica: el punto ya esta fuera del limite, pero la tolerancia
			-- todavia lo cubre, asi que no se le considera perdido. Es lo que
			-- permite explorar el borde sin morir.
			--
			-- La tolerancia NUNCA convierte en jugable un punto que esta fuera de
			-- la caja: solo evita que se declare perdido. Un margen que
			-- "perdonara" mas alla del limite seria un muro con holgura, que es
			-- justo lo que se prohibe.
			local p = { x = BOUNDS.maxX + 10, z = 0 }
			expect.toBe(Bounds.Classify(BOUNDS, p, 0), Bounds.Zone.OutOfBounds)
			expect.toBe(Bounds.Classify(BOUNDS, p, 20), Bounds.Zone.Margin)
			expect.toBe(Bounds.IsOutOfBounds(BOUNDS, p, 20), false)
		end)
	end)
end

return describeWorldBounds