const fs = require('fs');
const buf = fs.readFileSync('C:\\Users\\bdani\\AppData\\Local\\Temp\\kilo\\runtime_logs.json');
// Remove BOM and decode as UTF-16LE
let str = buf.toString('utf-16le');
// Find JSON start
let start = -1;
for (let i = 0; i < str.length; i++) {
    if (str[i] === '{' || str[i] === '[') {
        start = i;
        break;
    }
}
if (start === -1) {
    console.log('No JSON found');
    process.exit(1);
}
const j = JSON.parse(str.slice(start));
const entries = j.entries || j.result;
if (entries && entries.length) {
    console.log('Total entries:', entries.length);
    entries.slice(0, 100).forEach(e => {
        console.log(e.level + ': ' + e.message);
    });
} else {
    console.log('Keys:', Object.keys(j).join(', '));
}
