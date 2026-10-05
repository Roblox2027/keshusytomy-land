-- qa-respawn-state.lua
-- Estado REAL de los bloques con reaparicion pendiente, con el motivo exacto
-- que devuelve la propia regla `BlockRespawnRules.CanRespawn`.
--
-- Por que se imprime el MOTIVO y no solo el estado: un bloque que no vuelve
-- puede estar esperando el plazo, bloqueado por una entidad, con la generacion
-- obsoleta o con el mundo apagado. Sin el motivo, "no reaparece" no se puede
-- distinguir de "todavia no le toca".
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Rules = require(game.ReplicatedStorage.Shared.Libraries.BlockRespawnRules)

local now = os.clock()
local rows = {}

for b, reg in pairs(Destruction._records) do
	if reg.ReadyAt > 0 then
		local vivo = b:GetAttribute("IsDestroyed") == false
		local ctx = {}
		ctx.generation = reg.Generation
		ctx.worldActive = Destruction._worldActive
		ctx.hasActiveCopy = vivo
		ctx.hasBlockingEntity = Destruction.hasBlockingEntity(b)

		local pode, motivo = Rules.CanRespawn(reg, now, ctx)
		local piece = vivo and "VIVO" or string.format("faltan%.0fs", reg.ReadyAt - now)

		table.insert(rows, string.format(
			"%s=%s[estado=%s vivo=%s pode=%s motivo=%s gen=%d]",
			b.Name,
			piece,
			tostring(reg.State),
			tostring(vivo),
			tostring(pode),
			tostring(motivo),
			reg.Generation
		))
	end
end

table.sort(rows)

return string.format(
	"t=%.0f mundoActivo=%s :: %s",
	now,
	tostring(Destruction._worldActive),
	table.concat(rows, " | ")
)