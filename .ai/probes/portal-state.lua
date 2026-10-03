local portalService = require(
	game:GetService("ServerScriptService").Services:WaitForChild("PortalService")
)

local out = {}
out.ids = table.concat(portalService.GetPortalIds(), ",")

-- `GetPortal` es la API PUBLICA: leer el portal por ella es legitimo y evita
-- tener que meter las manos en la tabla privada del servicio.
out.portals = {}

for _, worldId in ipairs(portalService.GetPortalIds()) do
	local portal = portalService.GetPortal(worldId)
	local threshold = portal.Threshold

	table.insert(out.portals, worldId .. " umbral=" .. tostring(threshold and threshold.Name or "NINGUNO")
		.. " pos=" .. tostring(portal.Position)
		.. " size=" .. tostring(threshold and threshold.Size or "-")
		.. " lvl=" .. tostring(portal.RequiredLevel)
		.. " estado=" .. tostring(portal.State))
end

return out