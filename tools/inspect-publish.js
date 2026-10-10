// inspect-publish.js
// Lista metodos del PublishService

const mcp = require("./mcp");

const CODE = `
local PublishService = game:GetService("PublishService")
local mt = getmetatable(PublishService)
local methods = {}
for k, v in pairs(mt.__index) do
	if type(v) == "function" then
		table.insert(methods, k)
	end
end
return methods
`;

(async () => {
	const out = await mcp.tool("execute_luau", {
		operation_id: "inspect-publish-" + Date.now(),
		code: CODE,
		target: "edit",
	});
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
