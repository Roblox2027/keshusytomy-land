// split-import.js
// Extrae cada contenedor top-level del build de Rojo como un .rbxm independiente.
// Usa el extractItem de sync-workspace.js (probado) para cada hijo de Workspace.
// Luego importa cada chunk por separado al MCP (< 39MB cada uno).

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const mcp = require("./mcp");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const BUILD = path.join(CACHE, "workspace-build.rbxlx");
const CHUNK_LIMIT = 35 * 1024 * 1024;

// Construir el build de Rojo
console.log("=== rojo build ===");
execFileSync(ROJO, ["build", "default.project.json", "-o", BUILD], {
    cwd: ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
});
console.log("Build completado.");

const xml = fs.readFileSync(BUILD, "utf8");

// Patron para encontrar <Item class="Folder"> con <string name="Name">VALUE</string>
// dentro de </Properties>, a profundidad 1 desde el Workspace root.
function extractNamedFolder(xml, className, wantedName) {
    const openRe = new RegExp(`<Item class="(?:${className})"(\\s[^>]*)?>`, "g");
    let match;

    while ((match = openRe.exec(xml)) !== null) {
        const start = match.index;

        // Verificar nombre dentro de Properties de ESTE item
        const propsEnd = xml.indexOf("</Properties>", start);
        if (propsEnd === -1) continue;

        const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
            xml.slice(start, propsEnd)
        );
        if (!nameMatch || nameMatch[1] !== wantedName) continue;

        // Contar depth para encontrar el cierre
        let depth = 1;
        let i = start + match[0].length;

        while (i < xml.length && depth > 0) {
            const nextOpen = xml.indexOf("<Item ", i);
            const nextClose = xml.indexOf("</Item>", i);

            if (nextClose === -1) throw new Error("Subarbol sin cerrar");
            if (nextOpen !== -1 && nextOpen < nextClose) {
                depth += 1;
                i = nextOpen + 6;
            } else {
                depth -= 1;
                i = nextClose + 7;
            }
        }

        return xml.slice(start, i);
    }

    throw new Error(`No se encontro <Item class="${className}"> llamado "${wantedName}"`);
}

// Extraer el Workspace root para obtener su cuerpo
const workspaceItem = extractNamedFolder(xml, "Workspace", "Workspace");

// Encontrar el cuerpo del Workspace (despues de </Properties>)
const propsEnd = workspaceItem.indexOf("</Properties>");
const bodyStart = workspaceItem.indexOf(">", propsEnd) + 1;
const bodyEnd = workspaceItem.lastIndexOf("</Item>");
const workspaceBody = workspaceItem.slice(bodyStart, bodyEnd);

// Extraer cada contenedor top-level del cuerpo del Workspace
// Escanear por items a profundidad 1
const items = [];
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

let depth = 0;
let itemStart = -1;

for (const t of tokens) {
    if (t.type === "open") {
        if (depth === 0) itemStart = t.pos;
        depth++;
    } else {
        depth--;
        if (depth === 0 && itemStart !== -1) {
            const content = workspaceBody.slice(itemStart, t.end);
            const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
                workspaceBody.slice(itemStart, itemStart + 5000)
            );
            const name = nameMatch ? nameMatch[1] : "item_" + items.length;
            items.push({
                name,
                content,
                byteSize: Buffer.byteLength(content, "utf8"),
            });
            itemStart = -1;
        }
    }
}

console.log("\nContenedores top-level del Workspace:");
for (const it of items) {
    console.log(`  ${it.name}: ${(it.byteSize / 1024 / 1024).toFixed(2)} MB`);
}

// Si Worlds es muy grande, dividirlo en mundos individuales
let finalItems = [];
for (const it of items) {
    if (it.name === "Worlds" && it.byteSize > CHUNK_LIMIT) {
        console.log("\nDividiendo Worlds en mundos individuales...");
        // Extraer mundos del contenido de Worlds
        const worldsBody = (() => {
            const pEnd = it.content.indexOf("</Properties>");
            const bStart = it.content.indexOf(">", pEnd) + 1;
            const bEnd = it.content.lastIndexOf("</Item>");
            return it.content.slice(bStart, bEnd);
        })();

        const worldTokens = [];
        const wRe = /<Item\b[^>]*>|<\/Item>/g;
        let wm;
        while ((wm = wRe.exec(worldsBody)) !== null) {
            worldTokens.push({
                type: wm[0].startsWith("</Item>") ? "close" : "open",
                pos: wm.index,
                end: wm.index + wm[0].length,
            });
        }

        let wDepth = 0;
        let wStart = -1;
        for (const t of worldTokens) {
            if (t.type === "open") {
                if (wDepth === 0) wStart = t.pos;
                wDepth++;
            } else {
                wDepth--;
                if (wDepth === 0 && wStart !== -1) {
                    const content = worldsBody.slice(wStart, t.end);
                    const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
                        worldsBody.slice(wStart, wStart + 5000)
                    );
                    const name = nameMatch ? nameMatch[1] : "world_" + finalItems.length;
                    finalItems.push({
                        name,
                        content,
                        byteSize: Buffer.byteLength(content, "utf8"),
                    });
                    wStart = -1;
                }
            }
        }

        console.log("Mundos extraídos:");
        for (const w of finalItems) {
            if (w.name === "Forest" || w.name === "Desert" || w.name === "Ice" || w.name === "Volcano" || w.name === "Cyber") {
                console.log(`  ${w.name}: ${(w.byteSize / 1024 / 1024).toFixed(2)} MB`);
            }
        }
    } else if (it.name !== "Terrain" && it.name !== "Camera") {
        // Saltamos Terrain y Camera (no son geometry)
        finalItems.push(it);
    }
}

// Agrupar chunks
const chunks = [];
let current = { items: [], size: 0 };
for (const it of finalItems) {
    const isWorld = it.name === "Forest" || it.name === "Desert" || it.name === "Ice" || it.name === "Volcano" || it.name === "Cyber";
    if (isWorld || (it.byteSize > CHUNK_LIMIT)) {
        // Mundo individual: chunk separado
        if (current.items.length > 0) {
            chunks.push(current);
            current = { items: [], size: 0 };
        }
        chunks.push({ items: [it], size: it.byteSize });
    } else {
        current.items.push(it);
        current.size += it.byteSize;
    }
}
if (current.items.length > 0) chunks.push(current);

console.log(`\nChunks generados: ${chunks.length}`);
const instanceId = process.env.MCP_INSTANCE_ID || "instance:jqu-ek9";

// Crear carpetas padre si es necesario
async function ensureParent(path) {
    const parts = path.split(".");
    let current = game.Workspace;
    for (let i = 0; i < parts.length - 1; i++) {
        let child = current:FindFirstChild(parts[i]);
        if (!child) {
            child = Instance.new("Folder");
            child.Name = parts[i];
            child.Parent = current;
        }
        current = child;
    }
}

// Importar cada chunk
let chunkIdx = 0;
for (const chunk of chunks) {
    const names = chunk.items.map((it) => it.name).join(", ");
    const mb = (chunk.size / 1024 / 1024).toFixed(2);
    console.log(`\nImportando chunk_${chunkIdx}: ${mb} MB [${names}]`);

    const rbxm =
        '<roblox version="4">\n' +
        '  <Item class="Folder">\n' +
        "    <Properties>\n" +
        '      <string name="Name">WorkspaceSource</string>\n' +
        "    </Properties>\n" +
        chunk.items.map((it) => it.content).join("") +
        "\n  </Item>\n" +
        "</roblox>\n";

    const outPath = path.join(CACHE, `workspace-chunk-${chunkIdx}.rbxm`);
    fs.writeFileSync(outPath, rbxm, "utf8");
    console.log(`  -> ${path.relative(ROOT, outPath)} (${(Buffer.byteLength(rbxm, "utf8") / 1024 / 1024).toFixed(2)} MB)`);

    // Determinar parent_path: los mundos van a game.Workspace.Worlds
    const allWorlds = chunk.items.every((it) =>
        ["Forest", "Desert", "Ice", "Volcano", "Cyber"].includes(it.name)
    );
    const parent = allWorlds ? "game.Workspace.Worlds" : "game.Workspace";

    // Crear la carpeta Worlds si es necesario
    if (allWorlds) {
        const createWorldsLua = `
local Workspace = game:GetService("Workspace")
local worlds = Workspace:FindFirstChild("Worlds")
if not worlds then
    worlds = Instance.new("Folder")
    worlds.Name = "Worlds"
    worlds.Parent = Workspace
end
return "Worlds folder ready"
`;
        const createRes = mcp.callToolSync("execute_luau", {
            code: createWorldsLua,
            instance_id: instanceId,
        });
        console.log("  " + (createRes || "Worlds creado"));
    }

    // Importar el chunk
    const argsFile = path.join(CACHE, `mcp-args-chunk-${chunkIdx}.json`);
    fs.writeFileSync(argsFile, JSON.stringify({
        source: { path: outPath },
        parent_path: parent,
        target: "edit",
    }), "utf8");

    const res = await mcp.callTool("import_rbxm", {
        arguments: JSON.parse(fs.readFileSync(argsFile, "utf8")),
        instance_id: instanceId,
    });
    console.log("  " + JSON.stringify(res).substring(0, 200));

    chunkIdx++;
}

console.log("\n=== Todos los chunks importados ===");
