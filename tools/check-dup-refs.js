const fs = require('fs');
const readline = require('readline');

async function main() {
    const rl = readline.createInterface({
        input: fs.createReadStream('KESHUSY-LAN-D.rbxlx'),
        crlfDelay: Infinity
    });
    
    const referents = {};
    const duplicates = [];
    let lineNum = 0;
    
    for await (const line of rl) {
        lineNum++;
        const m = line.match(/<Item class="Part" referent="(\d+)">/);
        if (m) {
            const ref = m[1];
            if (referents[ref]) {
                duplicates.push({ ref, first: referents[ref], second: lineNum });
            }
            referents[ref] = lineNum;
        }
    }
    
    console.log('Total Part items:', Object.keys(referents).length);
    if (duplicates.length === 0) {
        console.log('No duplicate referent IDs found');
    } else {
        console.log('DUPLICATE referent IDs:');
        for (const d of duplicates) {
            console.log('  ref=' + d.ref + ' first at line ' + d.first + ', second at line ' + d.second);
        }
    }
}

main();
