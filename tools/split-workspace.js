// split-workspace.js
// Divide workspace-source.rbxm en chunks importables al MCP (< 35MB cada uno).
// Estrategia:
//  1. Extrae los contenedores top-level (Environment, Lobby, SpawnLocations, Worlds)
//  2. Si Worlds es muy grande, lo divide por mundo (Forest, Desert, ...)
//  3. Agrupa todo en chunks < 35MB

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const SRC = path.join(CACHE, "workspace-source.rbxm");

const buf = fs.readFileSync(SRC, "utf8");
const CHUNK_LIMIT = 35 * 1024 * 1024;

/**
 * Escanea una seccionad con el token regex y devuelve los Items top-level
 * (profundidad 1) como { name, content, byteSize }.
 */
function extractTopLevelItems(xml, startSearchFrom) {
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

    // Encontrar el cuerpo: despues del primer </Properties> desde startSearchFrom
    const propsEnd = xml.indexOf("</Properties>", startSearchFrom);
    if (propsEnd === -1) return [];
    const bodyStart = xml.indexOf(">", propsEnd) + 1;
    const bodyEnd = xml.lastIndexOf("</Item>");

    // Filtrar tokens en el cuerpo
    const bodyTokens = tokens.filter((t) => t.pos >= bodyStart && t.pos < bodyEnd);

    const items = [];
    let depth = 0;
    let currentStart = -1;

    for (const t of bodyTokens) {
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

// 1. Extraer contenedores top-level del workspace
const topItems = extractTopLevelItems(buf, 0);
console.log("Contenedores top-level:");
for (const it of topItems) {
    console.log(`  ${it.name}: ${(it.byteSize / 1024 / 1024).toFixed(2)} MB`);
}

// 2. Si Worlds es muy grande, dividirlo por mundo
let allItems = [];
for (const item of topItems) {
    if (item.name === "Worlds" && item.byteSize > CHUNK_LIMIT) {
        // Extraer mundos individuales del contenido de Worlds
        // El contenido de Worlds es: <Item class="Folder" referent="N"><Properties>...<Item class="Folder" referent="M"><Properties><Name>Forest</Name>...</Properties>...hijos...</Item>...
        // Buscar el cuerpo de Worlds: despues de su </Properties>
        const worldsPropsEnd = item.content.indexOf("</Properties>");
        const worldsBodyStart = item.content.indexOf(">", worldsPropsEnd) + 1;
        const worldsBodyEnd = item.content.lastIndexOf("</Item>");

        // Extraer items top-level del cuerpo de Worlds
        const worldsSubItems = extractTopLevelItems(item.content, 0);
        console.log(`\nMundos dentro de Worlds:`);
        for (const w of worldsSubItems) {
            console.log(`  ${w.name}: ${(w.byteSize / 1024 / 1024).toFixed(2)} MB`);
        }

        // Cada mundo se convierte en un chunk independiente
        // Primero agrupar los items pequenos (Environment, Lobby, SpawnLocations)
        for (const other of topItems) {
            if (other.name !== "Worlds") {
                allItems.push(other);
            }
        }
        // Los mundos van como items individuales para importarlos por separado
        for (const w of worldsSubItems) {
            allItems.push(w);
        }
        console.log(`\nTotal items a importar: ${allItems.length}`);
    } else {
        allItems.push(item);
    }
}

// 3. Agrupar en chunks < 35MB
const chunks = [];
let current = { items: [], size: 0 };

for (const item of allItems) {
    if (item.byteSize > CHUNK_LIMIT) {
        console.error(`ADVERTENCIA: ${item.name} supera el limite (${(item.byteSize / 1024 / 1024).toFixed(2)} MB)`);
    }
    if (current.size + item.byteSize > CHUNK_LIMIT && current.items.length > 0) {
        chunks.push(current);
        current = { items: [], size: 0 };
    }
    current.items.push(item);
    current.size += item.byteSize;
}
if (current.items.length > 0) chunks.push(current);

console.log(`\nChunks generados: ${chunks.length}`);
for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    const mb = (chunk.size / 1024 / 1024).toFixed(2);
    const names = chunk.items.map((it) => it.name).join(", ");
    console.log(`  chunk_${i}: ${mb} MB [${names}]`);

    // Determinar parent_path: Environment/Lobby/SpawnLocations van a game.Workspace
    // Los mundos van a game.Workspace.Worlds (el chunk_0 crea Worlds)
    const isWorldChunk = chunk.items.every((it) => it.name.startsWith("Worlds") || it.name === "Forest" || it.name === "Desert" || it.name === "Ice" || it.name === "Volcano" || it.name === "Cyber");

    const rbxm =
        '<roblox version="4">\n' +
        '  <Item class="Folder">\n' +
        "    <Properties>\n" +
        '      <string name="Name">WorkspaceSource</string>\n' +
        "    </Properties>\n" +
        chunk.items.map((it) => it.content).join("") +
        "\n  </Item>\n" +
        "</roblox>\n";

    const outPath = path.join(CACHE, `workspace-chunk-${i}.rbxm`);
    fs.writeFileSync(outPath, rbxm, "utf8");
    console.log(`    -> ${path.relative(ROOT, outPath)} (${(Buffer.byteLength(rbxm, "utf8") / 1024 / 1024).toFixed(2)} MB)`);
}
