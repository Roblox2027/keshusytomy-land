const fs = require('fs');
const path = require('path');
const proj = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'default.project.json'), 'utf-8'));

const lobby = proj.tree.Workspace.Lobby;
const workspaceLobby = 'Workspace.Lobby';

// Collect all parts under Lobby (direct children + children of KeshusyCore and Portals folders)
const fixes = [];

function visit(node, parentPath) {
    if (!node || typeof node !== 'object') return;
    for (const key of Object.keys(node)) {
        if (key === '$className' || key === '$properties') continue;
        const child = node[key];
        if (!child || typeof child !== 'object') continue;
        const props = child.$properties || {};
        if (child.$className === 'Part' && props.Position) {
            const pos = props.Position;
            const rounded = pos.map(v => Math.round(v * 1000) / 1000);
            fixes.push({
                name: key,
                path: parentPath + '.' + key,
                position: rounded,
            });
        }
        // Recurse into folders
        if (child.$className === 'Folder' || child.$className === 'Model') {
            visit(child, parentPath + '.' + key);
        }
    }
}

// Direct children of Lobby
visit(lobby, workspaceLobby);

// Generate Lua script to fix positions
let luaLines = [];
luaLines.push('-- Fix lobby part positions from default.project.json');
luaLines.push('local Workspace = game:GetService("Workspace")');
luaLines.push('local lobby = Workspace:FindFirstChild("Lobby")');
luaLines.push('if not lobby then return "no lobby" end');
luaLines.push('');

for (const fix of fixes) {
    // Parse the path like "Workspace.Lobby.Lamp_8"
    const parts = fix.path.split('.').slice(1); // Remove "Workspace"
    let luaPath = 'lobby';
    for (let i = 1; i < parts.length; i++) {
        luaPath += ':FindFirstChild("' + parts[i] + '")';
    }
    luaLines.push('do');
    luaLines.push('    local obj = ' + luaPath);
    luaLines.push('    if obj and obj:IsA("Part") then');
    luaLines.push('        obj.Position = Vector3.new(' + fix.position.join(', ') + ')');
    luaLines.push('    end');
    luaLines.push('end');
}

luaLines.push('');
luaLines.push('return "Fixed ' + fixes.length + ' parts"');

const output = luaLines.join('\n');
fs.writeFileSync(path.join(__dirname, 'fix-lobby-positions.lua'), output);
console.log('Generated tools/fix-lobby-positions.lua with ' + fixes.length + ' fixes');
console.log('Parts to fix:');
for (const f of fixes) {
    console.log('  ' + f.path + ' -> ' + JSON.stringify(f.position));
}
