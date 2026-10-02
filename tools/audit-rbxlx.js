// Audit helper: prints the real instance tree of a Rojo-built .rbxlx.
// Usage: node tools/audit-rbxlx.js <file.rbxlx> [--paths name1,name2]
const fs = require("fs");

const file = process.argv[2];
const src = fs.readFileSync(file, "utf8");

const root = { cls: "DataModel", name: "(root)", children: [] };
const stack = [root];

const tokenRe = /<Item class="([A-Za-z0-9_]+)"[^>]*>|<\/Item>/g;
let m;
while ((m = tokenRe.exec(src)) !== null) {
	if (m[0] === "</Item>") {
		if (stack.length > 1) stack.pop();
		continue;
	}
	const cls = m[1];
	const start = m.index + m[0].length;
	// Property block lives right after the open tag, before any child <Item>.
	const nextItem = src.indexOf("<Item ", start);
	const propBlock = src.slice(start, nextItem === -1 ? src.length : nextItem);
	const props = {};
	const propRe = /<(\w+) name="([A-Za-z0-9_]+)"[^>]*>([^<]*)<\/\1>/g;
	let pp;
	while ((pp = propRe.exec(propBlock)) !== null) props[pp[2]] = pp[3];

	const name = props.Name !== undefined ? props.Name : "(noname)";
	const node = { cls: cls, name: name, props: props, children: [] };
	stack[stack.length - 1].children.push(node);
	stack.push(node);
}

function countNodes(n) {
	let total = 1;
	for (const c of n.children) total += countNodes(c);
	return total;
}

console.log("TOTAL INSTANCES: " + countNodes(root));
console.log("");

console.log("=== TREE (depth 2) ===");
(function print(n, depth) {
	if (depth > 2) return;
	for (const c of n.children) {
		console.log("  ".repeat(depth) + "- " + c.name + "  [" + c.cls + "]");
		print(c, depth + 1);
	}
})(root, 0);

const byName = new Map();
(function collect(n) {
	if (!byName.has(n.name)) byName.set(n.name, {});
	const e = byName.get(n.name);
	e[n.cls] = (e[n.cls] || 0) + 1;
	for (const c of n.children) collect(c);
})(root);

const paths = new Map();
(function index(n, prefix) {
	const p = prefix ? prefix + "/" + n.name : n.name;
	if (!paths.has(n.name)) paths.set(n.name, new Set());
	paths.get(n.name).add(p);
	for (const c of n.children) index(c, p);
})(root, "");

function readProps(block) {
	const props = {};
	const propRe = /<(\w+) name="([A-Za-z0-9_]+)"[^>]*>([^<]*)<\/\1>/g;
	let p;
	while ((p = propRe.exec(block)) !== null) props[p[2]] = p[3];
	return props;
}

if (process.argv.indexOf("--props") !== -1) {
	// Walk the parsed tree instead of re-scanning text: only real instances
	// are visited, never source code embedded inside a Script's Source.
	const arg = process.argv[process.argv.indexOf("--props") + 1];
	const want = arg.split(",");
	const keys = [
		"Position", "Size", "Anchored", "CanCollide", "CanTouch", "CanQuery",
		"Transparency", "Material", "Enabled", "Neutral", "Duration",
	];

	(function walk(n, path) {
		if (want.indexOf(n.name) !== -1) {
			const props = n.props || {};
			const shown = [];
			for (const key of keys) {
				if (props[key] !== undefined) shown.push(key + "=" + props[key]);
			}
			console.log(path + "  [" + n.cls + "]  " + shown.join("  "));
		}
		for (const c of n.children) walk(c, path + "/" + c.name);
	})(root, "");
}

console.log("");
console.log("=== NAME PRESENCE IN RBXLX ===");
const interesting = [
	"ReplicatedStorage", "Remotes", "Shared", "Config", "GameConfig",
	"PerformanceConfig", "FeatureConfig", "Constants", "GameConstants",
	"Utils", "Logger", "Libraries", "WorldDefinitions", "Lobby", "Worlds",
	"Forest", "Cyber", "Desert", "Ice", "Volcano", "SpawnLocations",
	"Environment", "ArenaFloor", "ArenaCenter", "LobbyCenter",
	"ServerScriptService", "ServerMain", "Services", "Systems",
	"ServiceRegistry", "RemoteGateway", "StarterPlayer", "StarterPlayerScripts",
	"ClientMain", "Controllers", "ControllerRegistry", "InputController",
	"StarterGui", "PlayerAction", "BombAction", "ShopAction", "InventoryAction",
	"QuestAction", "PortalAction", "PartyAction", "SettingsAction",
];

for (const key of interesting) {
	const e = byName.get(key);
	if (!e) {
		console.log("MISSING : " + key);
	} else {
		console.log("OK      : " + key + "  -> " + Object.keys(e)
			.map(function (c) { return c + " x" + e[c]; }).join(", "));
	}
}

if (process.argv.indexOf("--paths") !== -1) {
	const arg = process.argv[process.argv.indexOf("--paths") + 1];
	for (const key of arg.split(",")) {
		const set = paths.get(key);
		console.log("");
		console.log("PATHS for '" + key + "':");
		if (!set) {
			console.log("  (none)");
		} else {
			const arr = Array.from(set);
			for (let i = 0; i < arr.length && i < 20; i++) console.log("  " + arr[i]);
		}
	}
}

console.log("");
console.log("=== ALL DISTINCT NAMES ===");
const keys = Array.from(byName.keys()).sort();
for (const k of keys) {
	const e = byName.get(k);
	console.log(k + "  -> " + Object.keys(e)
		.map(function (c) { return c + " x" + e[c]; }).join(", "));
}