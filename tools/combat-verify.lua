-- Verify the destruction and damage chain against the REAL map.
--
-- Run by tools/combat-verify.js. It lives in its own file on purpose: keeping
-- the Luau out of the JavaScript avoids a template literal, which is the only
-- construct that can misinterpret a `$` or a backtick inside the snippet and
-- silently turn code into text.
--
-- NO SE COLOCAN BOMBAS DESDE AQUI
-- --------------------------------
-- El puente MCP de Studio rechaza `Instance:AddChild()` con "AddChild is not
-- a valid member of Folder". Se comprobo que el receptor es una Instance
-- valida (es el mismo Folder que Workspace.Bombs), que `x.Parent = folder` SI
-- funciona sobre ese mismo Folder y que incluso asignar `folder.AddChild = ...`
-- falla igual. Es una limitacion del puente, no de BombService.
--
-- Por eso este recorrido mide lo que no necesita crear instancias: la cadena
-- de reglas, el dano y la destruccion de bloques.

local Players = game:GetService("Players")
local GC = require(game:GetService("ReplicatedStorage").Shared.Config.GameConfig)
local GameConstants = require(game:GetService("ReplicatedStorage").Shared.Constants.GameConstants)
local Bomb = require(game:GetService("ServerScriptService").Services.BombService)
local Combat = require(game:GetService("ServerScriptService").Services.CombatService)
local Dest = require(game:GetService("ServerScriptService").Services.DestructionService)
local Round = require(game:GetService("ServerScriptService").Services.RoundService)

local RoundState = GameConstants.RoundState
local out = { steps = {}, destruction = {} }

local function note(k, v)
    out.steps[#out.steps + 1] = k .. " = " .. tostring(v)
end

local player = Players:GetPlayers()[1]
if not player then
    return { error = "no hay jugador" }
end

local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local root = character and character:FindFirstChild("HumanoidRootPart")
if not humanoid or not root then
    return { error = "personaje incompleto" }
end

note("ronda inicial", Round.GetState())
if Round.GetState() == RoundState.Waiting then
    Round.Transition(RoundState.Countdown)
    Round.Transition(RoundState.RoundStarting)
    Round.Transition(RoundState.Playing)
end
note("ronda", Round.GetState())
note("IsPlaying", Round.IsPlaying())

local forest = game:GetService("Workspace").Worlds.Forest
local arenaCenter = forest:FindFirstChild("ArenaCenter")
root.CFrame = CFrame.new(arenaCenter.Position + Vector3.new(0, 4, 0))
note("jugador en la arena", string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z))

-- A bomb placed far from the player must be refused: that guard is testable
-- without creating any instance.
local faraway, farReason = Bomb.TryPlaceBomb(player, Vector3.new(0, 500, 0))
note("bomba a 500 studs", tostring(faraway) .. " (" .. tostring(farReason) .. ")")

local function visibleBlocks()
    local n = 0
    for _, d in ipairs(forest:GetDescendants()) do
        if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Block_" and d.Transparency < 1 then
            n += 1
        end
    end
    return n
end

out.destruction.before = visibleBlocks()
out.destruction.registered = Dest.CollectBlocks()

local blocks = forest:FindFirstChild("Blocks")
local targetBlock
for _, c in ipairs(blocks:GetChildren()) do
    if c:IsA("BasePart") and Dest.IsDestructibleBlock(c) then
        targetBlock = c
        break
    end
end

if not targetBlock then
    return { error = "no hay bloques en Forest.Blocks" }
end

out.destruction.block = targetBlock.Name
out.destruction.transparencyBefore = targetBlock.Transparency
out.destruction.canCollideBefore = targetBlock.CanCollide

-- Drive the block to destruction.
--
-- CORRECTION DE LA PRIMERA VERSION DE ESTA PRUEBA
-- -----------------------------------------------
-- El bucle se apoyaba en el valor devuelto por `ApplyDamage` para decidir si
-- seguir, y lo interpretaba como "el bloque sigue en pie". Eso es INVERSO: la
-- funcion devuelve `true` justo cuando lo DESTRUYE, y `false` mientras
-- sobrevive.
--
-- Con la logica equivocada, el primer golpe (vida 100 -> 40) devolvia `false`,
-- el bucle lo leia como "ya no esta vivo" y se salia tras UN impacto. El
-- bloque nunca llegaba a 0 y la comprobacion reportaba FAIL sobre un servicio
-- que en realidad estaba bien.
--
-- Ahora el bucle continua mientras `ApplyDamage` devuelva `false` (el bloque
-- aguanta) y para cuando devuelva `true` (lo destruye), que es exactamente la
-- firma del metodo.
local perBomb = GC.DefaultBombDamage * GC.BlockDamageScale
note("dano por bomba", perBomb)
note("vida del bloque", GC.BlockHealth)

local hits = 0
local destroyedNow = false

-- `ApplyDamage` devuelve true CUANDO destruye, false mientras sobrevive.
while hits < 20 do
    local destroyedThisHit = Dest.ApplyDamage(targetBlock, perBomb)
    hits = hits + 1
    out.destruction.healthAfterHit = Dest.GetBlockHealth(targetBlock)
    if destroyedThisHit then
        destroyedNow = true
        break
    end
end

out.destruction.destroyedOnHit = hits
out.destruction.hits = hits
out.destruction.finalHealth = Dest.GetBlockHealth(targetBlock)
out.destruction.transparencyAfter = targetBlock.Transparency
out.destruction.canCollideAfter = targetBlock.CanCollide
out.destruction.after = visibleBlocks()
out.destruction.destroyedCount = Dest.GetDestroyedBlockCount()

-- The `IsDestroyed` attribute is what the rest of the game reads.
out.destruction.isDestroyedAttr = targetBlock:GetAttribute("IsDestroyed")

Dest.RestoreAll()
out.destruction.afterRestore = visibleBlocks()
out.destruction.transparencyRestored = targetBlock.Transparency
out.destruction.collideRestored = targetBlock.CanCollide
out.destruction.destroyedAfterRestore = Dest.GetDestroyedBlockCount()

out.combat = {
    hasApplyDamage = type(Combat.ApplyDamage) == "function",
}

return out
