"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Hud = require("./hud");

const root = path.join(__dirname, "..");
const project = JSON.parse(fs.readFileSync(path.join(root, "default.project.json"), "utf8"));
const generatedHud = Hud.buildHud().node;
const projectHud = project.tree.StarterGui.KeshusyHUD;
const channels = ["Master", "Music", "Sfx", "Ambience", "UI"];

assert.deepStrictEqual(projectHud, generatedHud, "default.project.json HUD differs from tools/hud.js output");

const audioToggle = projectHud.Root.TopBar.Bar.AudioToggle;
assert.strictEqual(audioToggle.$className, "TextButton", "Audio settings toggle is missing");

const panel = projectHud.Root.Overlays.AudioSettings;
assert.strictEqual(panel.$className, "Frame", "Audio settings panel is missing");
assert.strictEqual(panel.$properties.Visible, false, "Audio settings panel must start closed");

for (const channel of channels) {
    const row = panel[channel + "Row"];
    assert.ok(row, `${channel} slider row is missing`);
    assert.strictEqual(row.Slider.$className, "TextButton", `${channel} slider is not interactive`);
    assert.ok(row.Slider.Fill, `${channel} slider fill is missing`);
    assert.ok(row.Value, `${channel} value label is missing`);
}

console.log("AUDIO UI CONTRACT: PASS (generator synchronized; five interactive volume channels)");
