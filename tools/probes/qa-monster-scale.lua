-- qa-monster-scale.lua
-- Mide en PLAY el tamano REAL de cada monstruo y lo compara con el jugador.
--
-- Por que una sonda y no una prueba de unidad: `MonsterScale.spec` comprueba
-- que los NUMEROS declarados estan dentro de los rangos, pero no que el
-- modelo que se dibuja en pantalla mida eso. Aqui se mide `Body.Size` (lo que
-- se ve) y `Root.Size` (lo que colisiona) de los modelos vivos.
--
-- Ademas comprueba la SEPARACION: la raiz tiene que ser estrictamente menor
-- que el cuerpo. Si fueran iguales, un Guardian seria un muro.
--
-- HALLO QUE ESTA SONDA CERRADO (medido en PLAY)
-- -----------------------------------------------
-- Cuatro bichos salian MAS BAJOS que el jugador: Slime 4.20, BombBug 3.64,
-- Bomber 4.42 y Hunter 5.27 contra un jugador de 5.50. La causa no estaba en
-- las cifras declaradas, que eran correctas, sino en que `VisualKit`
-- multiplicaba la escala por la FORMA base (un cubo de ~3 studs) en vez de
-- por el jugador. Corregido en `MonsterScaleRules.BodySize`.
local Players = game:GetService("Players")
local MonsterService = require(game.ServerScriptService.Services.MonsterService)
local Definitions = require(game.ReplicatedStorage.Shared.MonsterDefinitions)
local ScaleRules = require(game.ReplicatedStorage.Shared.Libraries.MonsterScaleRules)

local out = {}
local folder = MonsterService.GetFolder()

-- ALTURA DE REFERENCIA: el jugador, medido en el mismo DataModel que los
-- monstruos. Comparar con un 1.0 de papel seria medir dos cosas distintas.
--
-- La medida es la CAJA del personaje, no `HipHeight + root.Size.Y`: esa
-- segunda formula da ~4.0 studs, y con ella el jugador mide mas bajo que un
-- Slime que en pantalla es mas alto. El fallo estaria en la referencia, no
-- en el bicho.
local player = Players:GetPlayers()[1]
local playerHeight = 0
local measuredBy = "ninguna"

if player and player.Character then
	local _, boundingSize = player.Character:GetBoundingBox()
	playerHeight = boundingSize.Y
	measuredBy = "caja del personaje"

	local hum = player.Character:FindFirstChildOfClass("Humanoid")

	if hum then
		measuredBy = ("caja + Humanoid (%s)"):format(hum.Health > 0 and "vivo" or "muerto")
	end
end

if playerHeight <= 0 then
	playerHeight = ScaleRules.PlayerHeightStuds
	measuredBy = "sin personaje: se usa la referencia declarada"
end

out[#out + 1] = ("jugador: %.2f studs de alto (medido por %s)"):format(playerHeight, measuredBy)

-- Mundo de la ronda actual, para leer el multiplicador real.
local worldId = player and player:GetAttribute("World") or nil
out[#out + 1] = ("mundo=%s multiplicador=%.2f"):format(
	tostring(worldId), ScaleRules.GetWorldScale(worldId))

local fallos = {}

for _, id in ipairs(Definitions.GetIds()) do
	-- Se genera MUY LEJOS del jugador para no alterar la ronda que se esta
	-- midiendo: los monstruos tienen IA y borrarlos todos mataria la partida.
	local anchor = Vector3.new(0, 5000, 0) + Vector3.new(#out * 20, 0, 0)
	local monsterId = MonsterService.Spawn(id, anchor, worldId)

	if not monsterId then
		table.insert(fallos, ("%s: Spawn devolvio nil (feature off, tope o MaxAlive)"):format(id))
		continue
	end

	-- Se espera a que termine la animacion de aparicion: `Spawn` escala el
	-- Body desde 0.4 hasta el tamano final en 5 pasos de 0.05 s. Medir antes
	-- daria un modelo mas pequeno del que existe en pantalla, y la sonda
	-- reprobaria un monster que esta bien.
	task.wait(0.6)

	local record = MonsterService._monsters[monsterId]
	local model = record and record.Model or nil

	if not model or not model.Parent then
		table.insert(fallos, ("%s: el modelo no existe tras Spawn"):format(id))
		continue
	end

	local body = model:FindFirstChild("Body")
	local root = model.PrimaryPart
	local hum = model:FindFirstChildOfClass("Humanoid")

	if not body or not body:IsA("BasePart") or not root or not root:IsA("BasePart") then
		table.insert(fallos, ("%s: modelo sin Body/Root utilizables"):format(id))
		model:Destroy()
		continue
	end

	-- Dos medidas, y no son la misma:
	--
	--   * `bodyH`   = la caja del `Body`. Es lo que el jugador lee como "el
	--     bicho", y es contra esta medida que esta escrito el contrato de
	--     `MonsterScaleRules`: `HitboxScale` es la proporcion de la hitbox
	--     respecto al MODELO.
	--   * `visualH` = la caja del modelo entero, con antenas, ojos y el aro de
	--     telegraph. Sirve para reporting, no para validar la hitbox.
	--
	-- Medir el contrato de la hitbox contra la caja completa daba 0.26-0.40 y
	-- reprobaba a los nueve bichos, cuando el mismo Root medido contra el
	-- `Body` da 0.65-0.85, justo lo declarado. La sonda estaba reprobando la
	-- denominacion equivocada.
	local _, visualBox = model:GetBoundingBox()
	local visualH = visualBox.Y
	local bodyH = body.Size.Y
	local hitboxH = root.Size.Y
	local ratio = hitboxH / math.max(bodyH, 0.001)
	local declaredVisual = ScaleRules.Resolve(id, worldId)

	out[#out + 1] = ("%-14s cuerpo %5.2f (x%.2f jug) modelo-caja %5.2f (x%.2f jug) | hitbox %5.2f | ratio %.2f | declarado x%.2f | vida %d"):format(
		id,
		bodyH,
		bodyH / playerHeight,
		visualH,
		visualH / playerHeight,
		hitboxH,
		ratio,
		declaredVisual,
		hum and hum.MaxHealth or -1)

	-- CONTRATO 1: el enemigo se lee como mas grande que el jugador. Se compara
	-- el CUERPO, no la caja entera: comparar con la caja incluyendo antenas y
	-- aro de telegraph deja pasar a un bicho cuya silueta es mas baja que la
	-- del jugador, que es justo lo que este contrato quiere evitar.
	if bodyH <= playerHeight then
		table.insert(fallos, ("%s: cuerpo %.2f studs no supera al jugador (%.2f)"):format(id, bodyH, playerHeight))
	end

	-- CONTRATO 2: la hitbox esta acotada y es menor que el cuerpo.
	if ratio >= 1 then
		table.insert(fallos, ("%s: hitbox %.2f >= cuerpo %.2f, colisiona como se ve"):format(id, hitboxH, bodyH))
	end

	if ratio < ScaleRules.MinHitboxRatio - 0.001 then
		table.insert(fallos, ("%s: hitbox %.3f por debajo del minimo %.2f, se puede atravesar sin notar"):format(id, ratio, ScaleRules.MinHitboxRatio))
	end

	-- El bicho tiene que medir lo que DECLARA. Esta comparacion no existia y
	-- es la que habria pillado el fallo de escala: el numero y el tamano en
	-- studs son dos afirmaciones distintas sobre el mundo, y solo se comprueba
	-- que concordan midiendo.
	if math.abs(bodyH - ScaleRules.PlayerHeightStuds * declaredVisual) > 0.05 then
		table.insert(fallos, ("%s: mide %.2f studs pero declara x%.2f (esperaba %.2f)"):format(
			id, bodyH, declaredVisual, ScaleRules.PlayerHeightStuds * declaredVisual))
	end

	-- Limpieza: se saca el registro y se destruye el modelo SIN matar al
	-- Humanoid. Poner `Health = 0` dispara `Died` -> `OnMonsterDied`, que
	-- paga monedas y avisaria por el chat: la sonda contaminaria la economy
	-- de la ronda que se intenta medir.
	MonsterService._monsters[monsterId] = nil
	model:Destroy()
end

-- Verificacion final: la carpeta debe quedar como estaba.
local restantes = 0

for _, child in ipairs(folder:GetChildren()) do
	restantes += 1
end

out[#out + 1] = ("monstruos tras la sonda: %d"):format(restantes)

if #fallos == 0 then
	out[#out + 1] = "ESCALA: PASS"
else
	for _, f in ipairs(fallos) do
		out[#out + 1] = "FALLO " .. f
	end
	out[#out + 1] = ("ESCALA: FAIL (%d)"):format(#fallos)
end

return table.concat(out, "\n")
