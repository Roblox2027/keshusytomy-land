const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const INSTANCE = process.argv[2];
const FILE = process.argv[3];

(async () => {
	const code = fs.readFileSync(path.resolve(FILE), "utf8");
	const out = await mcp.tool("eval_server_runtime", { code, instance_id: INSTANCE });
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});