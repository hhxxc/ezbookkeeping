// Generate a trimmed moment-timezone data file.
//
// The default `import moment from 'moment-timezone'` bundles the FULL Olson
// database (every zone, every historical transition, up to year 2499). This app
// only needs timezones for real transaction dates (>= 2000) plus a small forward
// window, and it must keep ALL IANA zones correct (the user can pick any zone
// from ALL_TIMEZONES, and getBrowserTimezoneName() may return an arbitrary
// browser zone). So instead of dropping zones, we keep all zones but truncate
// the transition history to [START_YEAR, END_YEAR]. The output is committed so
// the build needs no extra step.
//
// Usage: node scripts/gen-timezone-data.cjs [outputPath]

const fs = require('fs');
const path = require('path');

const m = require('moment-timezone');
require('moment-timezone/moment-timezone-utils'); // attaches pack / filterYears onto m.tz
const full = require('moment-timezone/data/packed/latest.json');

const START_YEAR = 2000;
const END_YEAR = 2050;

const outZones = [];
for (const packed of full.zones) {
    const name = packed.split('|')[0];
    const zone = m.tz.zone(name); // unpacked Zone object with .untils
    if (!zone) {
        continue;
    }
    const trimmed = m.tz.filterYears(zone, START_YEAR, END_YEAR);
    outZones.push(m.tz.pack(trimmed));
}

const output = {
    version: full.version,
    zones: outZones,
    links: full.links.slice(),
    countries: full.countries ? full.countries.slice() : []
};

const outPath = path.resolve(process.argv[2] || 'src/lib/timezone-data-trimmed.json');
fs.writeFileSync(outPath, JSON.stringify(output));

const sizeRaw = fs.statSync(outPath).size;

// Pre-pack the synthetic "Fixed/Timezone{N}" zones used by datetime.ts for
// fixed UTC-offset handling. We compute these here (where the real `pack` is
// available) so the runtime only needs to call `moment.tz.add(packedString)`
// and never has to import moment-timezone-utils (which would re-pull the full
// Olson data build). Offsets must stay in sync with
// src/consts/timezone.ts (WESTERNMOST_TIMEZONE_UTC_OFFSET / EASTERNMOST_...).
const WESTERNMOST_TIMEZONE_UTC_OFFSET = -720; // Etc/GMT+12 (UTC-12:00)
const EASTERNMOST_TIMEZONE_UTC_OFFSET = 840;  // Pacific/Kiritimati (UTC+14:00)
const fixedZones = [];
for (let utcOffset = WESTERNMOST_TIMEZONE_UTC_OFFSET; utcOffset <= EASTERNMOST_TIMEZONE_UTC_OFFSET; utcOffset += 15) {
    const timezoneName = `Fixed/Timezone${utcOffset}`;
    fixedZones.push(m.tz.pack({
        name: timezoneName,
        abbrs: [`FIX${utcOffset}`],
        offsets: [-utcOffset],
        untils: [0]
    }));
}
const fixedOutPath = path.resolve(process.argv[3] || 'src/lib/fixed-timezones.json');
fs.writeFileSync(fixedOutPath, JSON.stringify(fixedZones));

// Verify against a CORE (no-data) moment instance to confirm the trimmed file
// loads and resolves real zones correctly.
const coreM = require('moment-timezone/moment-timezone.js');
coreM.tz.load(output);

function check(name, dateStr) {
    const z = coreM.tz.zone(name);
    if (!z) return name + ': MISSING';
    return name + ': offset=' + z.utcOffset(new Date(dateStr)) + 'min';
}

const checks = [
    check('Asia/Shanghai', '2026-01-15'),
    check('Asia/Tokyo', '2026-07-15'),
    check('America/New_York', '2026-01-15'),
    check('America/New_York', '2026-07-15'),
    check('Europe/London', '2026-07-15'),
    check('Asia/Calcutta', '2026-01-15'),
    check('Australia/Sydney', '2026-07-15'),
    check('Pacific/Kiritimati', '2026-01-15'),
    check('Etc/GMT+12', '2026-01-15'),
    check('America/Sao_Paulo', '2026-01-15')
];

console.log('full zones:', full.zones.length, 'trimmed zones:', output.zones.length);
console.log('trimmed raw bytes:', sizeRaw, '(~' + Math.round(sizeRaw / 1024) + ' KB)');
console.log('checks:');
checks.forEach(c => console.log('  ' + c));

const fullChecks = checks.map(c => {
    const name = c.split(':')[0];
    const z = m.tz.zone(name);
    return name + ' full=' + (z ? z.utcOffset(new Date('2026-07-15')) : 'MISSING');
});
console.log('full-build offsets (2026-07-15, for cross-check):');
fullChecks.forEach(c => console.log('  ' + c));
