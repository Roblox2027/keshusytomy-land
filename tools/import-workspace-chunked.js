// import-workspace-chunked.js
// Variante de import_rbxm que divide el workspace-source.rbxm en chunks < 35MB
// (el limite del MCP) e importa cada uno por separado.
//
// El workspace completo supera con creces los 39MB del MCP porque Worlds
// contiene 5 mundos con ~42K partes. Este script:
//  1. Extrae los contenedores top-level (Environment, Lobby, SpawnLocations, Worlds)
//  2. Si Worlds supera el limite, lo divide por mundo (Forest, Desert, ...)
//  3. Importa el chunk base (Environment+Lobby+SpawnLocations+Worlds vacio)
//  4. Ejecuta merge-workspace para unwrappear el wrapper
//  5. Importa cada mundo a game.Workspace.Worlds
//  6. Desenrolla los wrappers WorkspaceSource dentro de Worlds
//  7. Ejecuta dedupe-workspace
//
// Uso: node tools/import-workspace-chunked.js [instance_id]

"use strict";

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const SRC = path.join(CACHE, "workspace-source.rbxm");
const CHUNK_LIMIT = 35 * 1024 * 1024;

const instanceId = process.argv[2] || process.env.MCP_INSTANCE_ID || null;

/**
 * Escanea un XML rbxm y extrae los <Item> a profundidad 1 (hijos directos
 * del Folder raiz), devolviendo { name, content, byteSize } por cada uno.
 */
function extractTopLevel(xml) {
    const tokenRe = /<Item\b[^>]*>|<\/Item>/g;
    let m;
    const tokens = [];
    while ((m = tokenRe.exec(xml)) !== null) {
        tokens.push({
            type: m[0].startsWith("</Item>") ? "close" : "open",
            pos: m.index,
            end: m.index + m[0].length,
        });
    }

    const propsEnd = xml.indexOf("</Properties>");
    if (propsEnd === -1) return [];
    const bodyStart = xml.indexOf(">", propsEnd) + 1;
    const bodyEnd = xml.lastIndexOf("</Item>");

    const items = [];
    let depth = 0;
    let currentStart = -1;

    for (const t of tokens) {
        if (t.pos < bodyStart || t.pos >= bodyEnd) continue;
        if (t.type === "open") {
            if (depth === 0) currentStart = t.pos;
            depth++;
        } else {
            depth--;
            if (depth === 0 && currentStart !== -1) {
                const content = xml.slice(currentStart, t.end);
                const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
                    xml.slice(currentStart, currentStart + 5000)
                );
                const name = nameMatch ? nameMatch[1] : "item_" + items.length;
                items.push({
                    name,
                    content,
                    byteSize: Buffer.byteLength(content, "utf8"),
                });
                currentStart = -1;
            }
        }
    }

    return items;
}

/** Envuelve items en un rbxm con Folder raiz llamado WorkspaceSource. */
function wrapRbxm(items) {
    return (
        '<roblox version="4">\n' +
        '  <Item class="Folder">\n' +
        "    <Properties>\n" +
        '      <string name="Name">WorkspaceSource</string>\n' +
        "    </Properties>\n" +
        items.map((it) => it.content).join("") +
        "\n  </Item>\n" +
        "</roblox>\n"
    );
}

/** Escribe un chunk y lo importa al MCP. */
async function importChunk(items, parent, label) {
    const rbxm = wrapRbxm(items);
    const byteSize = Buffer.byteLength(rbxm, "utf8");
    const mb = (byteSize / 1024 / 1024).toFixed(2);

    if (byteSize > CHUNK_LIMIT) {
        throw new Error(`${label}: chunk de ${mb} MB excede el limite de ${CHUNK_LIMIT / 1024 / 1024} MB`);
    }

    const chunkPath = path.join(CACHE, `workspace-chunk-${label}.rbxm`);
    fs.writeFileSync(chunkPath, rbxm, "utf8");
    console.log(`  ${label}: ${mb} MB -> importando a ${parent}`);

    const argsFile = path.join(CACHE, `mcp-args-${label}.json`);
    fs.writeFileSync(
        argsFile,
        JSON.stringify({
            source: { path: chunkPath },
            parent_path: parent,
            target: "edit",
        }),
        "utf8"
    );

    const res = await mcp.toolJson("import_rbxm", JSON.parse(fs.readFileSync(argsFile, "utf8")));
    console.log("  " + JSON.stringify(res).substring(0, 300));
    return res;
}

async function main() {
    await mcp.init();

    console.log("Analizando workspace-source.rbxm...");
    const buf = fs.readFileSync(SRC, "utf8");
    const topItems = extractTopLevel(buf);

    console.log("Contenedores top-level:");
    for (const it of topItems) {
        console.log(`  ${it.name}: ${(it.byteSize / 1024 / 1024).toFixed(2)} MB`);
    }

    // Separar Worlds de los demas contenedores
    const worldsItem = topItems.find((it) => it.name === "Worlds");
    const nonWorldItems = topItems.filter((it) => it.name !== "Worlds" && it.name !== "Terrain" && it.name !== "Camera");

    // Si Worlds es muy grande, extraer mundos individuales
    let allChunks = [];

    if (worldsItem && worldsItem.byteSize > CHUNK_LIMIT) {
        console.log("\nWorlds supera el límite. Extrayendo mundos individualmente...");
        const worldItems = extractTopLevel(worldsItem.content);

        const worldsByName = {};
        for (const w of worldItems) {
            if (["Forest", "Desert", "Ice", "Volcano", "Cyber"].includes(w.name)) {
                worldsByName[w.name] = w;
            }
        }

        // Chunk base: Environment + Lobby + SpawnLocations + Worlds vacio.
        // Se construye Worlds vacio manualmente para evitar incluir los 42MB
        // de contenido de los mundos.
        const emptyWorldsItem = {
            name: "Worlds",
            content: '<Item class="Folder" referent="rw">\n      <Properties>\n        <string name="Name">Worlds</string>\n      </Properties>\n    </Item>',
            byteSize: 200,
        };

        // Chunk base con los contenedores no-world + Worlds vacío
        const baseItems = [...nonWorldItems, emptyWorldsItem];
        allChunks.push({ items: baseItems, parent: "game.Workspace", label: "base" });

        // Cada mundo como chunk separado
        for (const w of worldItems) {
            if (["Forest", "Desert", "Ice", "Volcano", "Cyber"].includes(w.name)) {
                allChunks.push({ items: [w], parent: "game.Workspace.Worlds", label: w.name });
            }
        }
    } else {
        // El workspace cabe en un chunk
        allChunks.push({ items: nonWorldItems, parent: "game.Workspace", label: "workspace" });
    }

    console.log(`\nChunks a importar: ${allChunks.length}`);

    // 1. Importar chunk base (Environment, Lobby, SpawnLocations, Worlds)
    const baseChunk = allChunks.find((c) => c.label === "base" || c.label === "workspace");
    if (baseChunk) {
        await importChunk(baseChunk.items, baseChunk.parent, baseChunk.label);
    }

    // 2. Merge-workspace para unwrappear WorkspaceSource
    console.log("\n=== merge-workspace ===");
    const mergeLua = fs.readFileSync(path.join(ROOT, "tools", "merge-workspace.lua"), "utf8");
    const mergeRes = await mcp.toolJson("execute_luau", { code: mergeLua, instance_id: instanceId });
    console.log("merge: " + JSON.stringify(mergeRes));

    // 3. Importar mundos individuales (si existen)
    const worldChunks = allChunks.filter((c) => c.label !== "base" && c.label !== "workspace");
    for (const chunk of worldChunks) {
        await importChunk(chunk.items, chunk.parent, chunk.label);
    }

    // 4. Desenrollar wrappers WorkspaceSource dentro de Worlds
    if (worldChunks.length > 0) {
        console.log("\n=== Unwrap WorkspaceSource en Worlds ===");
        const unwrapLua = `
local Workspace = game:GetService("Workspace")
local function unwrap(parent)
    local toDestroy = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("Folder") and child.Name == "WorkspaceSource" then
            for _, gc in ipairs(child:GetChildren()) do
                gc.Parent = parent
            end
            table.insert(toDestroy, child)
        elseif child:IsA("Folder") then
            unwrap(child)
        end
    end
    for _, d in ipairs(toDestroy) do d:Destroy() end
end
unwrap(Workspace)
return "Wrappers desenvueltos"
`;
        const unwrapRes = await mcp.toolJson("execute_luau", { code: unwrapLua, instance_id: instanceId });
        console.log("unwrap: " + JSON.stringify(unwrapRes));
    }

    // 5. Dedupe-workspace
    console.log("\n=== dedupe-workspace ===");
    const dedupeLua = fs.readFileSync(path.join(ROOT, "tools", "dedupe-workspace.lua"), "utf8");
    const dedupeRes = await mcp.toolJson("execute_luau", { code: dedupeLua, instance_id: instanceId });
    console.log("dedupe: " + JSON.stringify(dedupeRes));

    console.log("\n=== Chunked import completado ===");
}

main().catch((e) => {
    console.error("FALLO: " + e.message);
    process.exit(1);
});
