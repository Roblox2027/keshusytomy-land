// import-worlds.js
// Sincroniza el Workspace a Studio en chunks de < 35MB, divididos por mundo.
//
// El workspace completo es ~42MB (Worlds solo es ~42MB), lo que excede el
// limite de import_rbxm del MCP (~39MB). Este script extrae cada mundo por
// separado del build de Rojo y lo importa individualmente.
//
// Uso: node tools/import-worlds.js [instance_id]

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const mcp = require("./mcp");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const BUILD = path.join(CACHE, "workspace-build.rbxlx");
const CHUNK_LIMIT = 35 * 1024 * 1024;

const instanceId = process.argv[2] || process.env.MCP_INSTANCE_ID || null;

(async function main() {
// 1. Build de Rojo
console.log("=== rojo build ===");
fs.mkdirSync(CACHE, { recursive: true });
execFileSync(ROJO, ["build", "default.project.json", "-o", BUILD], {
    cwd: ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
});
console.log("Build completado.");

const xml = fs.readFileSync(BUILD, "utf8");

// 2. Extraer el Workspace root y sus hijos top-level
// Buscar <Item class="Workspace">...<Item class="Folder">...<Name>Environment</Name>...
const wsOpenRe = /<Item class="Workspace"(?:\s[^>]*)?>/;
const wsMatch = wsOpenRe.exec(xml);
if (!wsMatch) throw new Error("No se encontro <Item class=\"Workspace\">");

const wsStart = wsMatch.index;
// Encontrar el cierre balanceado del Workspace
let depth = 1;
let i = wsMatch.index + wsMatch[0].length;
while (i < xml.length && depth > 0) {
    const nextOpen = xml.indexOf("<Item ", i);
    const nextClose = xml.indexOf("</Item>", i);
    if (nextClose === -1) throw new Error("Workspace sin cerrar");
    if (nextOpen !== -1 && nextOpen < nextClose) {
        depth++;
        i = nextOpen + 6;
    } else {
        depth--;
        i = nextClose + 7;
    }
}
const workspaceXml = xml.slice(wsStart, i);

// Encontrar el cuerpo (despues de </Properties>)
const propsEnd = workspaceXml.indexOf("</Properties>");
const bodyStart = workspaceXml.indexOf(">", propsEnd) + 1;
const bodyEnd = workspaceXml.lastIndexOf("</Item>");
const workspaceBody = workspaceXml.slice(bodyStart, bodyEnd);

// 3. Extraer items top-level del cuerpo del Workspace
const items = [];
{
    const tokenRe = /<Item\b[^>]*>|<\/Item>/g;
    let m;
    const tokens = [];
    while ((m = tokenRe.exec(workspaceBody)) !== null) {
        tokens.push({
            type: m[0].startsWith("</Item>") ? "close" : "open",
            pos: m.index,
            end: m.index + m[0].length,
        });
    }

    let d = 0;
    let start = -1;
    for (const t of tokens) {
        if (t.type === "open") {
            if (d === 0) start = t.pos;
            d++;
        } else {
            d--;
            if (d === 0 && start !== -1) {
                const content = workspaceBody.slice(start, t.end);
                const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
                    workspaceBody.slice(start, start + 5000)
                );
                const name = nameMatch ? nameMatch[1] : "item_" + items.length;
                items.push({
                    name,
                    content,
                    byteSize: Buffer.byteLength(content, "utf8"),
                });
                start = -1;
            }
        }
    }
}

// Filtrar Terrain y Camera (no son geometry importable)
const filtered = items.filter((it) => it.name !== "Terrain" && it.name !== "Camera");

// Si Worlds es muy grande, dividirlo por mundo
const finalItems = [];
let worldsItem = null;
for (const it of filtered) {
    if (it.name === "Worlds" && it.byteSize > CHUNK_LIMIT) {
        worldsItem = it;
        // Extraer mundos del contenido de Worlds
        const wp = it.content.indexOf("</Properties>");
        const wb = it.content.indexOf(">", wp) + 1;
        const we = it.content.lastIndexOf("</Item>");
        const worldsBody = it.content.slice(wb, we);

        // Escanear items top-level en worldsBody
        const tokenRe = /<Item\b[^>]*>|<\/Item>/g;
        let m;
        const tokens = [];
        while ((m = tokenRe.exec(worldsBody)) !== null) {
            tokens.push({
                type: m[0].startsWith("</Item>") ? "close" : "open",
                pos: m.index,
                end: m.index + m[0].length,
            });
        }

        let d = 0;
        let start = -1;
        for (const t of tokens) {
            if (t.type === "open") {
                if (d === 0) start = t.pos;
                d++;
            } else {
                d--;
                if (d === 0 && start !== -1) {
                    const content = worldsBody.slice(start, t.end);
                    const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
                        worldsBody.slice(start, start + 5000)
                    );
                    const name = nameMatch ? nameMatch[1] : "world";
                    finalItems.push({
                        name,
                        content,
                        byteSize: Buffer.byteLength(content, "utf8"),
                    });
                    start = -1;
                }
            }
        }
        console.log("Mundos extraídos de Worlds:");
        for (const w of finalItems) {
            if (["Forest", "Desert", "Ice", "Volcano", "Cyber"].includes(w.name)) {
                console.log(`  ${w.name}: ${(w.byteSize / 1024 / 1024).toFixed(2)} MB`);
            }
        }
    } else {
        finalItems.push(it);
    }
}

// Separar items: non-world items (Environment, Lobby, SpawnLocations) vs worlds
const worldNames = new Set(["Forest", "Desert", "Ice", "Volcano", "Cyber"]);
const nonWorldItems = finalItems.filter((it) => !worldNames.has(it.name));
const worldItems = finalItems.filter((it) => worldNames.has(it.name));

// Agrupar non-world items en un chunk
const baseChunk = { items: nonWorldItems, size: nonWorldItems.reduce((a, b) => a + b.byteSize, 0) };

// 4. Crear la carpeta Worlds en Studio si no existe
console.log("\n=== Preparando Studio ===");
await mcp.init();

const resetLua = `
local Workspace = game:GetService("Workspace")
-- Limpiar el workspace si tiene restos del sync fallido
for _, name in ipairs({"Environment", "Lobby", "SpawnLocations", "Worlds"}) do
    local existing = Workspace:FindFirstChild(name)
    if existing then existing:Destroy() end
end
return "Workspace limpiado"
`;
const resetRes = await mcp.toolJson("execute_luau", { code: resetLua, instance_id: instanceId });
console.log("Reset: " + JSON.stringify(resetRes));

// 5. Importar chunk base (Environment, Lobby, SpawnLocations) + Worlds folder
const baseRbxm =
    '<roblox version="4">\n' +
    '  <Item class="Folder">\n' +
    "    <Properties>\n" +
    '      <string name="Name">WorkspaceSource</string>\n' +
    "    </Properties>\n" +
    baseChunk.items.map((it) => it.content).join("") +
    // Añadir un folder Worlds vacio para que los mundos tengan donde entrar
    '    <Item class="Folder">\n' +
    "      <Properties>\n" +
    '        <string name="Name">Worlds</string>\n' +
    "      </Properties>\n" +
    "    </Item>\n" +
    "\n  </Item>\n" +
    "</roblox>\n";

const basePath = path.join(CACHE, "workspace-chunk-base.rbxm");
fs.writeFileSync(basePath, baseRbxm, "utf8");
console.log(`\nChunk base: ${(Buffer.byteLength(baseRbxm, "utf8") / 1024 / 1024).toFixed(2)} MB`);

const baseArgsFile = path.join(CACHE, "mcp-args-base.json");
fs.writeFileSync(baseArgsFile, JSON.stringify({
    source: { path: basePath },
    parent_path: "game.Workspace",
    target: "edit",
}), "utf8");

console.log("Importando chunk base...");
const baseRes = await mcp.toolJson("import_rbxm", JSON.parse(fs.readFileSync(baseArgsFile, "utf8")));
console.log("  " + JSON.stringify(baseRes).substring(0, 300));

// 6. Importar cada mundo individualmente a game.Workspace.Worlds
for (const world of worldItems) {
    const worldRbxm =
        '<roblox version="4">\n' +
        '  <Item class="Folder">\n' +
        "    <Properties>\n" +
        '      <string name="Name">WorkspaceSource</string>\n' +
        "    </Properties>\n" +
        world.content +
        "\n  </Item>\n" +
        "</roblox>\n";

    const worldPath = path.join(CACHE, `workspace-${world.name}.rbxm`);
    fs.writeFileSync(worldPath, worldRbxm, "utf8");
    console.log(`\n${world.name}: ${(Buffer.byteLength(worldRbxm, "utf8") / 1024 / 1024).toFixed(2)} MB`);

    const worldArgsFile = path.join(CACHE, `mcp-args-${world.name}.json`);
    fs.writeFileSync(worldArgsFile, JSON.stringify({
        source: { path: worldPath },
        parent_path: "game.Workspace.Worlds",
        target: "edit",
    }), "utf8");

    console.log(`Importando ${world.name}...`);
    const res = await mcp.toolJson("import_rbxm", JSON.parse(fs.readFileSync(worldArgsFile, "utf8")));
    console.log("  " + JSON.stringify(res).substring(0, 300));
}

// 7. Ejecutar merge-workspace.lua y dedupe-workspace.lua
console.log("\n=== Fusionando y deduplicando ===");
const mergeLua = fs.readFileSync(path.join(ROOT, "tools", "merge-workspace.lua"), "utf8");
const mergeRes = await mcp.toolJson("execute_luau", { code: mergeLua, instance_id: instanceId });
console.log("merge-workspace: " + JSON.stringify(mergeRes));

const dedupeLua = fs.readFileSync(path.join(ROOT, "tools", "dedupe-workspace.lua"), "utf8");
const dedupeRes = await mcp.toolJson("execute_luau", { code: dedupeLua, instance_id: instanceId });
console.log("dedupe-workspace: " + JSON.stringify(dedupeRes));

// 8. Aplicar posiciones
console.log("\n=== Aplicando posiciones ===");
execFileSync("node", [path.join(ROOT, "tools", "apply-map-positions.js"), "--run"], {
    cwd: ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, MCP_INSTANCE_ID: instanceId || "instance:jqu-ek9" },
});

// 9. Verificar
console.log("\n=== Verificando ===");
const checkLua = `
local Workspace = game:GetService("Workspace")
local count = 0
local originParts = 0
for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA("BasePart") then
        count += 1
        local pos = d.Position
        if pos.Magnitude < 0.001 and d.Size.Magnitude > 20 then
            originParts += 1
        end
    end
end
return {totalParts=count, originParts=originParts}
`;
const checkRes = await mcp.toolJson("execute_luau", { code: checkLua, instance_id: instanceId });
console.log("Verificación: " + JSON.stringify(checkRes));

console.log("\n=== Import completado ===");
})(); // cierra async IIFE
