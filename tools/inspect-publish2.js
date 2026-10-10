// inspect-publish2.js
// Verifica metodos especificos del PublishService

const mcp = require("./mcp");

const CODE = `
local PublishService = game:GetService("PublishService")
return {
	publishToRoblox = PublishService.PublishToRoblox ~= nil,
	updateCurrentVersion = PublishService.UpdateCurrentVersion ~= nil,
	publishAsync = PublishService.PublishAsync ~= nil,
	getDefaultPlaceId = PublishService.GetDefaultPlaceId ~= nil,
	className = PublishService.ClassName,
}
`;

(async () => {
	const out = await mcp.tool("execute_luau", {
		operation_id: "inspect-publish2-" + Date.now(),
		code: CODE,
		target: "edit",
	});
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
