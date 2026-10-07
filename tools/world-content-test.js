"use strict";

const fs = require("fs");
const path = require("path");
const Worlds = require("./worlds");

const ROOT = path.join(__dirname, "..");
const project = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));
const miniBossSource = fs.readFileSync(
    path.join(ROOT, "src/ReplicatedStorage/Shared/Libraries/MiniBossRules.lua"),
    "utf8"
);
const WORLD_IDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];
const errors = [];

function flatten(node, prefix, output) {
    if (!node || typeof node !== "object") return;
    output.push({ path: prefix, node: node });
    for (const key of Object.keys(node)) {
        if (!key.startsWith("$") && node[key] && typeof node[key] === "object") {
            flatten(node[key], prefix ? prefix + "." + key : key, output);
        }
    }
}

const flat = [];
flatten(project.tree, "", flat);

for (const worldId of WORLD_IDS) {
    const layout = Worlds.LAYOUTS[worldId];
    const miniZoneIds = new Set(
        layout.zones.filter((zone) => zone.role === "miniboss").map((zone) => zone.id)
    );
    const secretZoneIds = new Set(
        layout.zones.filter((zone) => zone.role === "secret").map((zone) => zone.id)
    );
    if (miniZoneIds.size === 0) errors.push(`${worldId}: no dedicated miniboss zone in source layout`);
    if (secretZoneIds.size === 0) errors.push(`${worldId}: no secret zone in source layout`);

    const worldPrefix = `Workspace.Worlds.${worldId}.`;
    const miniMarkers = flat.filter((entry) => entry.path.startsWith(worldPrefix + "Zones.")
        && entry.path.endsWith("MiniBossSpawn_" + worldId + "_" + entry.path.split("_").pop()));
    for (const zoneId of miniZoneIds) {
        const expected = worldPrefix + `Zones.Zone_${worldId}_${zoneId}.MiniBossSpawn_${worldId}_${zoneId}`;
        if (!flat.some((entry) => entry.path === expected)) {
            errors.push(`${worldId}.${zoneId}: generated miniboss anchor missing`);
        }
    }

    for (const zoneId of secretZoneIds) {
        const expectedPrefix = worldPrefix + `Zones.Zone_${worldId}_${zoneId}.`;
        const prompt = flat.find((entry) => entry.path === expectedPrefix
            + `SecretCache_${worldId}_${zoneId}.SecretPrompt_${worldId}_${zoneId}`);
        if (!prompt || prompt.node.$className !== "ProximityPrompt") {
            errors.push(`${worldId}.${zoneId}: generated secret ProximityPrompt missing`);
            continue;
        }
        const props = prompt.node.$properties || {};
        if (!props.Enabled || props.MaxActivationDistance < 6 || props.HoldDuration <= 0) {
            errors.push(`${worldId}.${zoneId}: secret prompt has invalid interaction settings`);
        }
    }

    const block = miniBossSource.match(new RegExp(`\\n\\t${worldId} = \\{([\\s\\S]*?)\\n\\t\\},`));
    if (!block) {
        errors.push(`${worldId}: miniboss catalog section missing`);
        continue;
    }
    for (const match of block[1].matchAll(/Zone = "([A-Za-z0-9_]+)"/g)) {
        const zoneId = match[1];
        const zone = layout.zones.find((item) => item.id === zoneId);
        if (!zone) {
            errors.push(`${worldId}: miniboss catalog points to missing zone ${zoneId}`);
        } else if (!["encounter", "intermediate", "destruction", "miniboss"].includes(zone.role)) {
            errors.push(`${worldId}.${zoneId}: miniboss uses non-combat role '${zone.role}'`);
        }
    }
    console.log(`${worldId}: minibossZones=${miniZoneIds.size} secretZones=${secretZoneIds.size} prompt/anchor contracts checked`);
}

if (errors.length) {
    console.error("WORLD CONTENT: FAIL");
    for (const error of errors) console.error(" - " + error);
    process.exit(1);
}

console.log("WORLD CONTENT: PASS");