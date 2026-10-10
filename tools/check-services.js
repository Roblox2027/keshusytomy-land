const fs = require('fs');
const path = require('path');

// Check what's in src/ServerScriptService
const servicesDir = path.join(__dirname, '..', 'src', 'ServerScriptService');
console.log('=== ServerScriptService structure ===');

function walkDir(dir, prefix) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const relPath = prefix + entry.name;
        if (entry.isDirectory()) {
            console.log('  ' + relPath + '/');
            walkDir(fullPath, '  ' + relPath + '/');
        } else {
            console.log('  ' + relPath);
        }
    }
}

walkDir(servicesDir, '');

// Check default.project.json for ServerScriptService
console.log('\n=== default.project.json ServerScriptService ===');
const proj = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'default.project.json'), 'utf-8'));
const sss = proj.tree.ServerScriptService;
if (sss) {
    console.log('$className:', sss.$className);
    console.log('$path:', sss.$path);
    console.log('Keys:', Object.keys(sss).filter(k => !k.startsWith('$')));
} else {
    console.log('ServerScriptService not found in project');
}
