// deploy-mcp.js
// Publica el lugar actual de Studio a Roblox usando el MCP.
//
// Uso: node tools/deploy-mcp.js
//
// Requisitos: Roblox Studio abierto con el MCP conectado, Rojo sincronizado.
// Si el lugar no esta publicado (PlaceId = 0), PublicService crea uno nuevo.

const mcp = require("./mcp");

const PUBLISH_CODE = `
local PublishService = game:GetService("PublishService")
local result = { ok = false, placeId = game.PlaceId, gameId = game.GameId, message = "" }

if game.PlaceId ~= 0 then
	result.ok = true
	result.message = "El lugar ya esta publicado con PlaceId=" .. game.PlaceId
	return result
end

local ok, err = pcall(function()
	PublishService:PublishToRoblox()
end)
result.ok = ok
result.message = ok and "Publicado correctamente" or ("Error: " .. tostring(err))

wait(2)

result.placeId = game.PlaceId
result.gameId = game.GameId
return result
`;

(async () => {
	const out = await mcp.tool("execute_luau", {
		operation_id: "deploy-publish-" + Date.now(),
		code: PUBLISH_CODE,
		target: "edit",
	});
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
