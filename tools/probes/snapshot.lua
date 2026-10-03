-- snapshot.lua
-- Instantanea del servidor en ejecucion. Solo LECTURA: no cambia el juego.
local out = {}
local function line(s) out[#out+1] = tostring(s) end

local Players = game:GetService("Players")
local list = Players:GetPlayers()
line("jugadores=" .. #list)

for _, p in ipairs(list) do
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	line(string.format("  %s vida=%s pos=%s World=%s", p.Name,
		hum and math.floor(hum.Health) or "nil",
		root and tostring(root.Position) or "nil",
		tostring(p:GetAttribute("World"))))
end

local function grab(name)
	local ok, m = pcall(require, game.ServerScriptService.Services[name])
	if not ok then return nil end
	return m
end

local Round = grab("RoundService")
if Round then
	line("ronda=" .. tostring(Round.GetState())
		.. "  numero=" .. tostring(Round.GetRoundNumber())
		.. "  vivos=" .. tostring(Round.GetAliveCount()))
	line("  atascos=" .. tostring(Round._stallCount)
		.. "  motivo=" .. tostring(Round._lastReason))
	-- El historial crece sin limite: solo se lee la cola.
	local hist = Round.State:GetHistory()
	local tail = {}
	for i = math.max(1, #hist - 6), #hist do tail[#tail+1] = hist[i] end
	line("  historial(cola)=" .. table.concat(tail, ">"))
end

local Monster = grab("MonsterService")
if Monster then line("monstruos=" .. tostring(Monster.GetAliveCount())) end

local Bomb = grab("BombService")
if Bomb then line("bombas=" .. tostring(Bomb.GetActiveBombCount())) end

local Explosion = grab("ExplosionService")
if Explosion then line("explosiones=" .. tostring(Explosion.GetExplosionCount())) end

local Destruction = grab("DestructionService")
if Destruction then
	line("bloques: vivos=" .. tostring(Destruction.GetAliveBlockCount())
		.. " destruidos=" .. tostring(Destruction.GetDestroyedBlockCount()))
end

-- DONDE ESTAN los bloques. Una bomba puede explotar sin tocar ninguno si el
-- mapa no los tiene donde llega el radio: hay que ver coordenadas, no conteos.
local blocks = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Block_" then
		blocks[#blocks+1] = d
	end
end
table.sort(blocks, function(a, b) return a.Name < b.Name end)
line("bloques en el mapa=" .. #blocks)
for i = 1, math.min(4, #blocks) do
	line(string.format("  %s en (%.0f, %.0f, %.0f) colision=%s",
		blocks[i].Name, blocks[i].Position.X, blocks[i].Position.Y, blocks[i].Position.Z,
		tostring(blocks[i].CanCollide)))
end

-- La lista REAL de stubs: un modulo sin metodos de dominio es una declaracion
-- de interfaz, no un sistema. Se cuenta, no se deduce.
local stubs = {}
for _, child in ipairs(game.ServerScriptService.Services:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		local hasDomain = false
		if ok and type(mod) == "table" then
			for k, v in pairs(mod) do
				if type(v) == "function" and k ~= "Init" and k ~= "Destroy" then
					hasDomain = true
					break
				end
			end
		end
		if ok and not hasDomain then stubs[#stubs+1] = child.Name end
	end
end
table.sort(stubs)
line("servicios SIN IMPLEMENTAR (" .. #stubs .. "): " .. table.concat(stubs, ", "))

return table.concat(out, "\n")