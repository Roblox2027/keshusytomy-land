const fs = require('fs');
    const rl = readline.createInterface({
        input: fs.createReadStream('KESHUSY-LAN-D.rbxlx'),
        crlfDelay: Infinity
    });
    async function main() {
        const counts = {};
        for await (const line of rl) {
            const m = line.match(/<Item class="Part" referent="(\d+)">/);
            if (m) {
                counts[m[1]] = (counts[m[1]] || 0) + 1;
            }
        }
    // But readline doesn't work this way...</think>