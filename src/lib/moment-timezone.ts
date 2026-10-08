// Single shared moment-timezone instance for the app.
//
// We deliberately import the CORE (no-data) build of moment-timezone and then
// load a trimmed dataset (scripts/gen-timezone-data.cjs -> timezone-data-trimmed.json)
// that keeps EVERY IANA zone but truncates transition history to 2000..2050.
//
// Why not just `import moment from 'moment-timezone'`? That entry pulls the FULL
// Olson database (all zones, all historical transitions, up to year 2499) into
// the bundle, which is the bulk of the moment chunk. Trimming the history keeps
// every timezone correct (the user can pick any zone from ALL_TIMEZONES, and
// getBrowserTimezoneName() may return an arbitrary browser zone) while shrinking
// the payload dramatically.
//
// The deep import below has no bundled type declarations.
// @ts-ignore
import moment from 'moment-timezone/moment-timezone.js';
import trimmedData from './timezone-data-trimmed.json';

moment.tz.load(trimmedData);

export default moment;
