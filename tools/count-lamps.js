const fs = require('fs');
const readline = require('readline');
async function main() {
    const counts = {};
    const rl = readline.createInterface({
        input: fs.createReadStream('KESHUSY-LAN-D.rbxlx'),
        crlfDelay: Infinity
    });
    rl.on('line', (line) => {
        const m = line.match(/name="Name">Lamp_(\d+)/);
        if (m) {
            const n = 'Lamp_' + m[1];
            counts[n] = (counts[n] || 0) + 1;
        }
    });
    await new Promise(resolve => rl.on('close', resolve));
    for (const k of Object.keys(counts).sort()) {
        console.log(k + ': ' + counts[k]);
    }
}
main();
