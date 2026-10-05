"use strict";

// p0-new-module.js
// Crea en el DataModel de Studio los ModuleScript NUEVOS del repositorio.
//
// POR QUE EXISTE
// --------------
// `tools/sync-scripts.js` reescribe el FUENTE de los scripts que ya existen en
// el arbol, pero no puede crear una instancia que no esta. Un modulo nuevo
// (este caso `BombButtonLayout.lua`) se quedaria sin sincronizar y el
// `require` del cliente fallaria en el siguiente arranque, con un error que
// no senala el archivo bueno.
//
// El Rojo de esta sesion no esta conectado al lugar abierto, asi que el arbol
// hay que actualizarlo a mano.
//
// MEDIDO: importar un `.rbxm` con el fuente dentro deja el `Source` VACIO en
// el arbol. Por eso la creacion y la escritura del fuente son pasos
// separados, y el segundo es el que se verifica. Un modulo existente pero
// sin fuente es peor que uno ausente: el fallo aparece lejos y sin relacion.
//
// Uso:
//   node tools/p0-new-module.js

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const ROOT = path.join(__dirname, "..");
const REPO_MODULE = "src/ReplicatedStorage/Shared/Libraries/BombButtonLayout.lua";
const PARENT_PATH = "ReplicatedStorage.Shared.Libraries";
const MODULE_NAME = "BombButtonLayout";

async function main() {
const source = fs.readFileSync(path.join(ROOT, REPO_MODULE), "utf8");

await mcp.init();

const instancePath = PARENT_PATH + "." + MODULE_NAME;
const found = JSON.stringify((await mcp.tool("search_objects", { query: MODULE_NAME })) || "");
const exists = found.indexOf(MODULE_NAME) !== -1 && found.indexOf("ModuleScript") !== -1;

if (!exists) {
const modelPath = path.join(ROOT, ".cache", "p0-layout-module.rbxm");
fs.mkdirSync(path.dirname(modelPath), { recursive: true });

const xml = [
'<roblox version="4">',
'<Item class="ModuleScript" referent="RBX0">',
"<Properties>",
"<string name=\"Name\">" + MODULE_NAME + "</string>",
'<token name="Source"><![CDATA[' + source + "]]></token>",
"<string name=\"Attributes\"><![CDATA[]]></string>",
"</Properties>",
"</Item>",
"</roblox>",
].join("\n");

fs.writeFileSync(modelPath, xml, "utf8");

const imported = await mcp.tool("import_rbxm", {
source: { path: modelPath },
parent_path: PARENT_PATH,
});
console.log("INSTANCIA  " + JSON.stringify(imported).slice(0, 200));
} else {
console.log("YA EXISTE  " + instancePath);
}

const written = await mcp.tool("set_script_source", { instancePath, source });
console.log("FUENTE     " + JSON.stringify(written).slice(0, 200));

const back = JSON.stringify((await mcp.tool("get_script_source", { instancePath })) || "");
const ok = back.indexOf("return Layout") !== -1 && back.indexOf("ReferenceResolutions") !== -1;

console.log("VERIFICADO " + (ok ? "PASS" : "FAIL"));
if (!ok) process.exitCode = 1;
}

main().catch((e) => {
console.error("FALLO: " + e.message);
process.exit(1);
});