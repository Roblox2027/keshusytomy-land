--!strict
--[[
	BombButton.spec
	Pruebas del BOTON DE BOMBA.

	POR QUE EXISTE
	--------------
	El boton era un `TextButton` rojo de 96x96 con el texto "BOMBA". Eso
	describe una ACCION pero no un OBJETO: el jugador tiene que traducir
	"rectangulo rojo = explosive" antes de poder usarlo.

	Estas pruebas comprueban dos cosas distintas y ambas importan:
	1. La geometria tiene cuerpo, tapa, mecha y chispa (NO es un circulo).
	2. Los estados son distinguibles entre si (el boton "dime lo que pasa").

	El punto 2 es el que mas fallos atrapa: si `Blocked` y `Cooldown` se
	viesen igual, el jugador veria un boton gris y pensaria que esta roto,
	cuando en realidad lo que puede es que no le quede ninguna bomba.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Button = require("../../src/ReplicatedStorage/Shared/Libraries/BombButtonRules")

--- Las pruebas de RESPONSIVE y de NO SOLAPAMIENTO viven ahora en
--- `HudLayout.spec.lua`: la bomba es una ZONA del HUD, no un `ScreenGui`
--- paralelo con su propia cuenta de posiciones, y esa cuenta era la que
--- divergia. Aqui solo queda la FORMA de la bomba y sus estados.

--- Mezcla dos colores hacia `Muted`. Es la MISMA cuenta que hace el
--- controlador al aplicar `Dim`, escrita aqui para poder comprobar que un
--- estado bloqueado se ve de verdad mas apagado que uno disponible.
--- @param color table { R, G, B }
--- @param muted table { R, G, B }
--- @param dim number
--- @return number brillo
local function brightness(color: any, muted: any, dim: number): number
	return (color.R + color.G + color.B) / 3 * (1 - dim) + (muted.R + muted.G + muted.B) / 3 * dim
end

	Harness.describe("BombButtonRules: el tiempo de rechazo es utilizable", function()
		Harness.it("el motivo de rechazo dura lo suficiente para leerse", function()
			-- Menos de un segundo no se lee; mas de cinco deja el boton
			-- mentido cuando el jugador ya puede volver a usarlo.
			expect.toBe(Button.Timing.RejectionDuration >= 1.5, true)
			expect.toBe(Button.Timing.RejectionDuration <= 5, true)
		end)
	end)

local function describeBombButton()
	Harness.describe("BombButtonRules: la geometria es una BOMBA", function()
		Harness.it("el boton tiene cuerpo, franja, tapa, mecha y chispa", function()
			-- Esta es la asercion CENTRAL del cambio de diseno: si el boton
			-- se dibuja con estas cinco piezas, no puede ser "un circulo con
			-- un texto" por muy rojo que fuera antes.
			local parts = Button.Geometry()

			expect.toBe(parts.Body ~= nil, true)
			expect.toBe(parts.Band ~= nil, true)
			expect.toBe(parts.Top ~= nil, true)
			expect.toBe(parts.Fuse ~= nil, true)
			expect.toBe(parts.Spark ~= nil, true)
		end)

		Harness.it("la mecha sale ARRIBA de la tapa y la chispa mas arriba", function()
			-- El orden vertical es lo que hace que se lea como bomba. Si la
			-- chispa quedara debajo del cuerpo, el boton seria un bol con
			-- un punto naranja dentro.
			local parts = Button.Geometry()

			expect.toBe(parts.Top.Position.Y < parts.Body.Position.Y, true)
			expect.toBe(parts.Fuse.Position.Y < parts.Top.Position.Y, true)
			expect.toBe(parts.Spark.Position.Y < parts.Fuse.Position.Y, true)
		end)

		Harness.it("la chispa queda sobre el ANCHO de la bomba, no al centro", function()
			-- Una mecha centrada parece una antena. La bomba real tiene la
			-- mecha ladeada, y es parte de por que se reconoce.
			local parts = Button.Geometry()

			expect.toBe(parts.Fuse.Position.X > 0, true)
			expect.toBe(parts.Spark.Position.X > 0, true)
		end)

		Harness.it("la mecha esta ROTADA", function()
			-- Vertical y recta parece un palo clavado en la cabeza.
			expect.toBe(Button.Geometry().Fuse.Rotation ~= 0, true)
		end)

		Harness.it("las piezas caben dentro del tamano del boton", function()
			-- Si una pieza se sale, el HUD tapa el boton de bomba o el
			-- boton se sale de la pantalla en movil.
			local parts = Button.Geometry()
			local size = Button.Size

			for _, name in ipairs({ "Body", "Band", "Top", "Fuse", "Spark" }) do
				local part = parts[name]
				local width = if type(part.Size) == "number" then part.Size else part.Size.X

				expect.toBe(width <= size, true)
			end
		end)

		Harness.it("la geometria devuelve una tabla NUEVA en cada llamada", function()
			-- Si devolviera una tabla compartida, el controlador que la
			-- modificara contaminaria a todos los clientes siguientes.
			local first = Button.Geometry()
			first.Body.Position.X = 999

			expect.toBe(Button.Geometry().Body.Position.X, 0)
		end)
	end)

	Harness.describe("BombButtonRules: los estados son distinguibles", function()
		Harness.it("sin nada que lo impida, el boton esta LISTO", function()
			expect.toBe(Button.Resolve(true, 0, false, false), Button.State.Ready)
		end)

		Harness.it("con enfriamiento, el estado es COOLDOWN", function()
			expect.toBe(Button.Resolve(true, 1.2, false, false), Button.State.Cooldown)
		end)

		Harness.it("sin permiso para colocar, el estado es BLOCKED", function()
			-- `Cooldown = 0` a proposito: si "no puedes" se escondiera
			-- detras de "espera", estos dos casos serian el mismo boton.
			expect.toBe(Button.Resolve(false, 0, false, false), Button.State.Blocked)
		end)

		Harness.it("BLOCKED tiene prioridad sobre COOLDOWN", function()
			-- Sin vida no hay nada que esperar: un contador de segundos
			-- haria que el jugador esperara una espera que no va a acabar.
			expect.toBe(Button.Resolve(false, 3, false, false), Button.State.Blocked)
		end)

		Harness.it("pulsado gana a bloqueado y a enfriamiento", function()
			-- El dedo esta encima: el boton tiene que responder AHORA, no
			-- un frame mas tarde.
			expect.toBe(Button.Resolve(false, 9, true, false), Button.State.Pressed)
			expect.toBe(Button.Resolve(true, 9, true, false), Button.State.Pressed)
		end)

		Harness.it("colocado gana a TODO lo demas", function()
			-- La confirmacion del servidor tiene que verse aunque el
			-- enfriamiento ya haya empezado a contar.
			expect.toBe(Button.Resolve(false, 9, true, true), Button.State.Placed)
		end)

		Harness.it("cada estado muestra cuenta atras SOLO cuando toca", function()
			-- En `Blocked` y en `Ready` no hay nada que contar, asi que el
			-- texto va en su sitio y no inventa un numero.
			expect.toBe(Button.Appearance(Button.State.Cooldown, 2).ShowCountdown, true)
			expect.toBe(Button.Appearance(Button.State.Blocked, 0).ShowCountdown, false)
			expect.toBe(Button.Appearance(Button.State.Ready, 0).ShowCountdown, false)
			expect.toBe(Button.Appearance(Button.State.Placed, 0).ShowCountdown, false)
		end)

		Harness.it("el enfriamiento MUESTRA los segundos que faltan", function()
			-- Sin esto el boton se apaga sin explicar nada y parece roto.
			expect.toBe(Button.Appearance(Button.State.Cooldown, 1.5).Label, "1.5")
		end)

		Harness.it("LISTO esta mas brillante que BLOQUEADO", function()
			-- La asercion de que los estados se DISTINGUEN de verdad. Con
			-- los dos iguales, el jugador no sabe si puede usarlo.
			local ready = Button.Appearance(Button.State.Ready, 0)
			local blocked = Button.Appearance(Button.State.Blocked, 0)
			local muted = Button.Palette.Muted

			expect.toBe(
				brightness(ready.Band, muted, ready.Dim) > brightness(blocked.Band, muted, blocked.Dim),
				true
			)
			expect.toBe(blocked.Dim > ready.Dim, true)
		end)

		Harness.it("BLOQUEADO apaga la chispa", function()
			-- Una chispa titilando sobre un boton que no hace nada es la
			-- senal mas fuerte de "pulsame" que se puede mandar mal.
			expect.toBe(Button.Appearance(Button.State.Blocked, 0).SparkVisible, false)
			expect.toBe(Button.Appearance(Button.State.Cooldown, 1).SparkVisible, false)
			expect.toBe(Button.Appearance(Button.State.Ready, 0).SparkVisible, true)
		end)

		Harness.it("pulsado y colocado ENCIENDEN la chispa", function()
			-- El feedback tiene que verse: sin chispa, pulsar el boton no
			-- produce ninguna sensacion.
			expect.toBe(Button.Appearance(Button.State.Pressed, 0).SparkVisible, true)
			expect.toBe(Button.Appearance(Button.State.Placed, 0).SparkVisible, true)
		end)

		Harness.it("la chispa crece al colocar: el feedback MASCARA el boton", function()
			-- "Salio" se lee como un fogonazo en el boton, sin necesidad de
			-- mirar el mundo.
			local pressed = Button.Appearance(Button.State.Pressed, 0)
			local placed = Button.Appearance(Button.State.Placed, 0)

			expect.toBe(placed.SparkScale > pressed.SparkScale, true)
			expect.toBe(placed.Label, "OK")
		end)

		Harness.it("la etiqueta secundaria muestra el ESTADO en reposo", function()
			-- El texto es secundario y pequeno, como pide el diseno: la
			-- bomba es el elemento visual principal.
			--
			-- MEDIDO EN PLAY (antes): decia "F", igual que `KeyHint`. Con los
			-- dos textos iguales, "listo" y "recargando" se veian IGUALES y
			-- el estado de la bomba no se leia nunca. El atajo lo dice
			-- `KeyHint`; esta etiqueta dice el estado.
			expect.toBe(Button.Appearance(Button.State.Ready, 0).Label, "LISTO")
		end)

		Harness.it("el texto del boton NUNCA es la palabra BOMBA", function()
			-- La asercion que ata el diseno viejo con el nuevo: el texto
			-- grande era "BOMBA" y ahora no aparece en ninguna etiqueta.
			local states = {
				Button.State.Ready,
				Button.State.Cooldown,
				Button.State.Blocked,
				Button.State.Pressed,
				Button.State.Placed,
			}

			for _, state in ipairs(states) do
				-- `toBeFalsy` y no `toBe(..., false)`: la asercion es que la
				-- etiqueta NO es la palabra "BOMBA" en ningun estado, y eso
				-- se comprueba con su negacion directa.
				expect.toBeFalsy(Button.Appearance(state, 1).Label == "BOMBA")
			end
		end)

		Harness.it("el cuerpo del boton NO es rojo", function()
			-- El diseno viejo era `Color3.fromRGB(220, 60, 60)`. Con un
			-- cuerpo rojo el boton vuelve a ser "el boton rojo", por muy
			-- dibujada que este la bomba encima.
			expect.toBe(Button.Palette.Body.R > 100, false)
		end)
	end)
Harness.describe("BombButtonRules: el latido de la chispa", function()
		Harness.it("la escala oscila dentro del rango declarado", function()
			local amount = Button.Timing.SparkPulseAmount
			local period = Button.Timing.SparkPulsePeriod

			for step = 0, 200 do
				local elapsed = (step / 200) * period * 2
				local scale = Button.SparkPulse(elapsed, period, amount)

				expect.toBe(scale >= 1 - 0.001, true)
				expect.toBe(scale <= 1 + amount + 0.001, true)
			end
		end)

		Harness.it("la chispa empieza en su minimo y termina en su maximo", function()
			-- Un ciclo que empieza y acaba en el mismo valor pareceria un
			-- pulso parado; uno que recorre los dos extremos se lee como
			-- "titila".
			local amount = Button.Timing.SparkPulseAmount
			local period = Button.Timing.SparkPulsePeriod

			expect.toBe(Button.SparkPulse(0, period, amount), 1)
			expect.toBe(Button.SparkPulse(period, period, amount), 1 + amount)
		end)

		Harness.it("el ciclo es CONTINUO: sin saltos entre latidos", function()
			-- La continuidad real es entre el FINAL de un ciclo y el
			-- PRINCIPIO del siguiente: `elapsed = 2 * periodo` debe dar lo
			-- mismo que `elapsed = 0`. Comparar el pico con el inicio
			-- comprobaria otra cosa (que la onda no varia), y pasaria solo
			-- por casualidad.
			--
			-- Se usa `toBeClose` con una tolerancia porque el instante del
			-- salto cae entre dos floats: comparar con `toBe` exigiria
			-- exactitud bit a bit y fallaria por aritmetica, no por
			-- logica.
			local period = Button.Timing.SparkPulsePeriod
			local amount = Button.Timing.SparkPulseAmount

			expect.toBeClose(
				Button.SparkPulse(period * 2, period, amount),
				Button.SparkPulse(0, period, amount),
				0.0001
			)
		end)

		Harness.it("un periodo CERO no revienta", function()
			-- Si `Timing.SparkPulsePeriod` se dejara a 0 al ajustar el
			-- balance, la division por cero aqui tumbaria el cliente.
			expect.toBe(Button.SparkPulse(1, 0, 0.2), 1)
		end)
	end)
end

return describeBombButton
