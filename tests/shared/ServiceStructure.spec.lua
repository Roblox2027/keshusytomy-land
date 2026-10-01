--!strict
--[[
	ServiceStructure.spec
	Regresion del BUG ESTRUCTURAL de `BombService` (auditoria final).

	Que paso:
	`BombService.lua` salio del commit anterior con bloques PEGADOS: las
	definiciones de `spawnBomb`, `GetPlayerBombCount` y `TryPlaceBomb`
	estan dentro del bucle de cadena de `detonateBomb`, y el archivo
	terminaba con un `end` huerfano. Luau lo aceptaba porque el codigo
	empalmado seguia siendo sintacticamente valido, asi que
	`luau-compile` daba EXIT 0 y los tests pasaban.

	El fallo era en tiempo de ejecucion: `Service.TryPlaceBomb`,
	`Service.Init`, `Service.Start` y `Service.Destroy` nunca se
	definian en el nivel superior, asi que `ServerMain` recibia `nil` y
	el servicio no arrancaba. Ni `luau-compile` ni los tests de logica
	podian detectarlo.

	Alcance honesto de ESTA prueba:
	El interprete `luau.exe` que ejecuta la suite no expone `io` ni
	`os.exit`, asi que desde aqui NO se pueden leer los fuentes de
	`src/`. Lo que se verifica en la suite es el DETECTOR: que
	distinga un fuente bien construido de uno empalmado. El escaneo
	real de los archivos lo ejecuta `tools/verify-structure.js`, que si
	puede abrir ficheros y devolver un codigo de salida distinto de cero.

	La regla es una sola, y esta en los dos sitios: una declaracion
	`function Service.X` debe estar en nivel superior (profundidad 0) y
	el archivo debe terminar en `return <Servicio>`.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

--- Elimina comentarios de bloque y de linea.
--- @param source string
--- @return string
local function stripComments(source: string): string
	local withoutBlocks = source:gsub("%-%-%[%[.-%]%]", function(block: string)
		return (block:gsub("[^\n]", " "))
	end)

	return (withoutBlocks:gsub("%-%-[^\n]*", ""))
end

--- Elimina cadenas de una linea.
--- @param line string
--- @return string
local function stripStrings(line: string): string
	local result = line:gsub('"(\\.|[^"\\])*"', '""')
	result = result:gsub("'(\\.|[^'\\])*'", "''")
	return result
end

--- Cuenta cuantas veces aparece un patron como palabra suelta.
---
--- La linea se envuelve con ESPACIOSSENTINELA y se busca con una clase
--- de caracteres en vez de con `^` / `$`: los anclajes de este Luau no
--- se comportan de forma fiable dentro de `gmatch` (un `(^|x)` al
--- principio de una linea no casa nunca), y el resultado era un
--- recuento de CERO en todas las palabras clave.
---
--- La clase de cierre acepta un caracter o el fin de la cadena (el
--- espacio anadido al final).
--- @param line string
--- @param pattern string patron SIN termino de palabra
--- @return number
local function countWord(line: string, pattern: string): number
	local padded = " " .. line .. " "
	local total = 0

	for _ in padded:gmatch("[^%w_.]" .. pattern .. "[%s%(%)%{},;]") do
		total += 1
	end

	return total
end

--- Cambio de profundidad que introduce una linea.
---
--- Se descuentan tres cosas que un conteo ingenuo confundiria:
---  1. El `do` de `for ... do` / `while ... do`: no abre bloque propio.
---  2. Las expresiones `if ... then ... else ...` de Luau: no llevan `end`.
---  3. Los `end` que aparecen dentro de cadenas o comentarios.
--- @param line string linea ya sin comentarios ni cadenas
--- @return number delta
local function depthDelta(line: string): number
	local opens = countWord(line, "[Ff]unction")
		+ countWord(line, "[Ii][Ff]")
		+ countWord(line, "[Ff][Oo][Rr]")
		+ countWord(line, "[Ww][Hh][Ii][Ll][Ee]")
		+ countWord(line, "[Dd][Oo]")

	local inlineDo = 0
	for _ in ((" " .. line .. " "):gmatch(
		"[^%w_.][Ff][Oo][Rr][^\n]-[^%w]%s+[Dd][Oo][^%w]"
	)) do
		inlineDo += 1
	end

	for _ in ((" " .. line .. " "):gmatch(
		"[^%w_.][Ww][Hh][Ii][Ll][Ee][^\n]-[^%w]%s+[Dd][Oo][^%w]"
	)) do
		inlineDo += 1
	end

	-- Expresion `if ... then ... else ...`: Luau NO le pone `end`, asi que
	-- abriria un bloque que nadie cierra.
	local ifExpressions = 0
	for _ in ((" " .. line .. " "):gmatch(
		"[^%w_][Ii][Ff][^\n]-%s+[Tt][Hh][Ee][Nn][^\n]-[^%w_][Ee][Ll][Ss][Ee][^%w]"
	)) do
		ifExpressions += 1
	end

	return opens - inlineDo - ifExpressions - countWord(line, "[Ee][Nn][Dd]")
end

--- Profundidad final de un fuente.
--- @param source string
--- @return number depth 0 si el fuente esta bien construido
local function measureDepth(source: string): number
	local depth = 0

	for line in (stripComments(source) .. "\n"):gmatch("(.-)\n") do
		depth += depthDelta(stripStrings(line))
	end

	return depth
end

--- Profundidad mas profunda en la que aparece una declaracion.
--- @param source string
--- @return number worst 0 si todas estan en nivel superior
local function worstDeclarationDepth(source: string): number
	local depth = 0
	local worst = 0

	for line in (stripComments(source) .. "\n"):gmatch("(.-)\n") do
		local trimmed = line:match("^%s*(.-)%s*$") or ""

		local isDeclaration = trimmed:match("^[Ff]unction%s+Service%.") ~= nil
			or trimmed:match("^local%s+[Ff]unction%s") ~= nil

		if isDeclaration and depth > worst then
			worst = depth
		end

		depth += depthDelta(stripStrings(line))
	end

	return worst
end

--- Ultima linea de codigo con contenido.
--- @param source string
--- @return string?
local function lastCodeLine(source: string): string?
	local last = nil

	for line in (stripComments(source) .. "\n"):gmatch("(.-)\n") do
		local trimmed = line:match("^%s*(.-)%s*$") or ""
		if trimmed ~= "" then
			last = trimmed
		end
	end

	return last
end

-- Fuente sano de referencia.
local HEALTHY = [[
local Service = {}

function Service.SetArenaBounds(bounds): number
	if not bounds then
		return 0
	end
	return bounds.MaxX
end

function Service.Init(): boolean
	Service.IsInitialized = true
	return true
end

return Service
]]

-- Reproduce la forma EXACTA del bug: una declaracion de nivel superior
-- caida dentro de un bucle. El `do` que se abre antes del empalme queda
-- cerrado por el `end` huerfano del final, de modo que la PROFUNDIDAD
-- TOTAL da 0: el archivo esta balanceado y Luau lo acepta. Por eso el
-- compilador NO ve nada raro y el fallo solo aparece al ejecutar.
local CORRUPTED = [[
local function detonateBomb(bombId, depth)
	for _, link in ipairs(chain) do
		if nextRecord then
			nextRecord.Depth = depth + 1

do
function Service.TryPlaceBomb(player, position)
	return true
end

			task.delay(link.Delay, function()
				detonateBomb(nextId, nextDepth)
			end)
		end
	end
end

-- El resto del archivo, que el empalmamiento se come por delante.
function Service.ClearBombs(): number
	return 0
end

return Service

end
]]

-- Un `if` usado como EXPRESION no lleva `end`: un conteo ingenuo lo
-- tomaria como bloque abierto y declararia sano un fuente roto.
local WITH_IF_EXPRESSION = [[
local function playerFromHumanoid(humanoid)
	if not humanoid then
		return nil
	end

	local killer = if type(id) == "number" then GetPlayer(id) else nil

	return killer
end

return Service
]]

-- Comentarios y cadenas que mencionan palabras clave.
-- Se usan delimitadores largos `[==[ ]==]` porque el contenido incluye
-- `]]`, que cerraria antes de tiempo una cadena `[[ ]]`.
local NOISY = [==[
--[[ un bloque que menciona function, end y if ]]
local Service = {} -- una linea con function y end
local texto = "end function if"
Service.IsInitialized = true
return Service
]==]

return function()
	Harness.describe("ServiceStructure", function()
		Harness.it("un fuente sano tiene profundidad 0", function()
			expect.toBe(measureDepth(HEALTHY), 0)
		end)

		Harness.it("un fuente sano declara todo en nivel superior", function()
			expect.toBe(worstDeclarationDepth(HEALTHY), 0)
		end)

		Harness.it("el empalmamiento no se ve en la profundidad total", function()
			-- El `end` final compensa el desbalance: por eso el total da 0
			-- y el compilador acepta el archivo. Solo el analisis por
			-- declaracion lo revela.
			expect.toBe(measureDepth(CORRUPTED), 0)
		end)

		Harness.it("el empalmamiento declara funciones dentro de un bloque", function()
			expect.toBe(worstDeclarationDepth(CORRUPTED) > 0, true)
		end)

		Harness.it("las expresiones if de Luau no se cuentan como bloque", function()
			expect.toBe(measureDepth(WITH_IF_EXPRESSION), 0)
		end)

		Harness.it("un 'end' huerfano final se detecta como imbalance", function()
			expect.toBe(measureDepth(HEALTHY .. "\nend\n"), -1)
		end)

		Harness.it("comentarios y cadenas no cuentan como codigo", function()
			expect.toBe(measureDepth(NOISY), 0)
			expect.toBe(worstDeclarationDepth(NOISY), 0)
		end)

		Harness.it("el ultimo codigo de un servicio es su return", function()
			expect.toBe(lastCodeLine(HEALTHY), "return Service")
		end)
	end)
end