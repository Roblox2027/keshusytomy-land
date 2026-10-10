const fs = require('fs');
const buf = fs.readFileSync('C:\\Users\\bdani\\AppData\\Local\\Temp\\kilo\\runtime_logs_start.json');
let str = buf.toString('utf-16le');
const start = str.indexOf('{');
str = str.slice(start);
const j = JSON.parse(str);
const entries = j.entries || [];
console.log('Total entries:', entries.length);
entries.slice(0, 50).forEach(e => {
    console.log(e.level + ': ' + e.message);
});
