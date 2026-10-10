// import-worlds-only.js
// Importa los 5 mundos individualmente a game.Workspace.Worlds.
// Asume que el chunk base y merge-workspace ya se han ejecutado.
//
// Uso: node tools/import-worlds-only.js [instance_id]

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const BUILD = path.join(CACHE, "workspace-build.rbxlx");

const instanceId = process.argv[2] || process.env.MCP_INSTANCE_ID || "instance:jqu-ek9";

// Los mundos ya fueron extraídos en la ejecución anterior.
// Buscarlos en .cache/
const worlds = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

(async function main() {
    await mcp.init();

    // Verificar que Worlds existe
    const checkWorlds = `
local Workspace = game:GetService("Workspace")
local worlds = Workspace:FindFirstChild("Worlds")
if not worlds then
    worlds = Instance.new("Folder")
    worlds.Name = "Worlds"
    worlds.Parent = Workspace
end
return "Worlds parented: " .. tostring(worlds.Parent.ClassName)
`;
    const checkRes = await mcp.toolJson("execute_luau", { code: checkWorlds, instance_id: instanceId });
    console.log("Worlds check: " + JSON.stringify(checkRes));

    // Leer la build y extraer cada mundo
    const xml = fs.readFileSync(BUILD, "utf8");

    // Extraer Workspace root
    const wsMatch = /<Item class="Workspace"(?:\s[^>]*)?>/.exec(xml);
    if (!wsMatch) throw new Error("No se encontro Workspace");

    const wsStart = wsMatch.index;
    let depth = 1;
    let i = wsStart + wsMatch[0].length;
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

    // Encontrar el cuerpo del Workspace
    const propsEnd = workspaceXml.indexOf("</Properties>");
    const bodyStart = workspaceXml.indexOf(">", propsEnd) + 1;
    const bodyEnd = workspaceXml.lastIndexOf("</Item>");
    const workspaceBody = workspaceXml.slice(bodyStart, bodyEnd);

    // Extraer Worlds item de workspaceBody
    // Buscar <Item class="Folder" ...> <string name="Name">Worlds</string>
    const worldsOpenRe = /<Item class="Folder"(?:\s[^>]*)?>\s*<Properties>\s*<string name="Name">Worlds<\/string>/;
    const wMatch = worldsOpenRe.exec(workspaceBody);
    if (!wMatch) throw new Error("No se encontro Worlds folder");

    const wStart = wMatch.index;
    depth = 1;
    i = workspaceBody.indexOf(">", wMatch.index + wMatch[0].length - 1) + 1;
    // Skip past "Worlds" property to find the opening tag end
    i = workspaceBody.indexOf(">", wMatch.index + wMatch[0].length) + 1;
    while (i < workspaceBody.length && depth > 0) {
        const nextOpen = workspaceBody.indexOf("<Item ", i);
        const nextClose = workspaceBody.indexOf("</Item>", i);
        if (nextClose === -1) throw new Error("Worlds sin cerrar");
        if (nextOpen !== -1 && nextOpen < nextClose) {
            depth++;
            i = nextOpen + 6;
        } else {
            depth--;
            i = nextClose + 7;
        }
    }
    const worldsXml = workspaceBody.slice(wStart, i);

    // Extraer mundos individuales de Worlds
    const wp = worldsXml.indexOf("</Properties>");
    const wb = worldsXml.indexOf(">", wp) + 1;
    const we = worldsXml.lastIndexOf("</Item>");
    const worldsBody = worldsXml.slice(wb, we);

    // Escanear items top-level en worldsBody
    const worldItems = [];
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
                if (worlds.includes(name)) {
                    worldItems.push({ name, content });
                }
                start = -1;
            }
        }
    }

    console.log(`Mundos a importar: ${worldItems.map(w => w.name).join(", ")}`);

    // Importar cada mundo
    for (const w of worldItems) {
        const rbxm =
            '<roblox version="4">\n' +
            '  <Item class="Folder">\n' +
            "    <Properties>\n" +
            '      <string name="Name">WorkspaceSource</string>\n' +
            "    </Properties>\n" +
            w.content +
            "\n  </Item>\n" +
            "</roblox>\n";

        const outPath = path.join(CACHE, `workspace-world-${w.name}.rbxm`);
        fs.writeFileSync(outPath, rbxm, "utf8");
        console.log(`\n${w.name}: ${(Buffer.byteLength(rbxm, "utf8") / 1024 / 1024).toFixed(2)} MB -> ${outPath}`);

        const args = {
            source: { path: outPath },
            parent_path: "game.Workspace.Worlds",
            target: "edit",
        };

        console.log(`Importando ${w.name}...`);
        const res = await mcp.toolJson("import_rbxm", args);
        const jsonStr = JSON.stringify(res);
        if (jsonStr.includes("error")) {
            console.log("  ERROR: " + jsonStr.substring(0, 400));
        } else {
            console.log("  OK: " + jsonStr.substring(0, 300));
        }
    }

    // Ejecutar dedupe-workspace después de importar todos
    console.log("\n=== Deduplicando ===");
    const dedupeLua = fs.readFileSync(path.join(ROOT, "tools", "dedupe-workspace.lua"), "utf8");
    const dedupeRes = await mcp.toolJson("execute_luau", { code: dedupeLua, instance_id: instanceId });
    console.log("dedupe: " + JSON.stringify(dedupeRes));

    // Aplicar posiciones
    console.log("\n=== Aplicando posiciones ===");
    const { execFileSync } = require("child_process");
    try {
        const out = execFileSync("node", [path.join(ROOT, "tools", "apply-map-positions.js"), "--run"], {
            cwd: ROOT,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env, MCP_INSTANCE_ID: instanceId },
        });
        console.log(out.substring(0, 500));
    } catch (e) {
        console.log("apply-map-positions error: " + e.message.substring(0, 300));
    }

    // Verificar
    console.log("\n=== Verificando ===");
    const checkLua = `
local Workspace = game:GetService("Workspace")
local count = 0
local originParts = 0
local missingPos = 0
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
    const verifyRes = await mcp.toolJson("execute_luau", { code: checkLua, instance_id: instanceId });
    console.log("Verificación: " + JSON.stringify(verifyRes));

    console.log("\n=== Import de mundos completado ===");
})();
