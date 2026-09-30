// `gsub` returns the string AND the number of replacements. A function whose
// body ends in a bare `return ...:gsub(...)` therefore returns TWO values, and
// in Lua the last value of an argument list or a table constructor EXPANDS.
//
// It has cost this resource twice. First `tonumber(bagName:gsub(...))` took the
// replacement count as tonumber's BASE. Then Framework.GetName, passed last to
// an INSERT, became two parameters and oxmysql refused the query — "expected 10
// parameters, but received 11", pointing at the query rather than at the name.
//
// The fix is a pair of parentheses, and the rule is: truncate at the source.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Natives and library calls that hand back more than one value. A `return` of
// any of these, unparenthesised, leaks the extras to the caller.
const MULTI = [
    'gsub', 'find', 'gmatch', 'pcall', 'xpcall', 'unpack', 'table.unpack',
    'GetModelDimensions', 'GetVehicleColours', 'GetVehicleExtraColours',
    'GetVehicleCustomPrimaryColour', 'GetVehicleCustomSecondaryColour',
    'GetActiveScreenResolution', 'GetShapeTestResult', 'GetVehicleNeonLightsColour',
    'GetVehicleTyreSmokeColor', 'GetGroundZFor_3dCoord',
];

// Is the whole expression inside one pair of brackets, which is what truncates
// it to a single value?
function wrapped(value) {
    if (!value.startsWith('(')) return false;

    let depth = 0;

    for (let i = 0; i < value.length; i += 1) {
        if (value[i] === '(') depth += 1;
        else if (value[i] === ')') {
            depth -= 1;

            // Closed before the end, so the opening bracket was grouping a
            // prefix rather than the whole thing.
            if (depth === 0) return i === value.length - 1;
        }
    }

    return false;
}

function walk(dir) {
    const full = path.join(ROOT, dir);
    if (!existsSync(full)) return [];

    const out = [];

    for (const name of readdirSync(full)) {
        const rel = `${dir}/${name}`;
        if (statSync(path.join(ROOT, rel)).isDirectory()) out.push(...walk(rel));
        else if (rel.endsWith('.lua')) out.push(rel);
    }

    return out;
}

const files = ['bridge', 'shared', 'client', 'server'].flatMap(walk);
const problems = [];
let scanned = 0;

// Lines that forward every value on purpose. The callback wrapper in db.lua
// has to hand back (ok, message) exactly as the handler returned it.
const ALLOW = new Set([
    'server/db.lua|return table.unpack(results, 2)',
]);

for (const file of files) {
    const lines = readFileSync(path.join(ROOT, file), 'utf8').split(/\r?\n/);

    for (const [index, line] of lines.entries()) {
        const code = line.replace(/--.*$/, '');

        const returned = code.match(/^\s*return\s+(.*)$/);
        if (!returned) continue;

        scanned += 1;

        const value = returned[1].trim();

        // Already truncated? Only if the FIRST bracket closes at the very end.
        // `return ('%s %s'):format(...)` also starts with a bracket and is not
        // truncated at all — that exact line is what this checker missed on its
        // first run, which is why it now counts depth instead of looking.
        if (wrapped(value)) continue;
        if (ALLOW.has(`${file}|return ${value}`)) continue;

        for (const call of MULTI) {
            const escaped = call.replace('.', '\\.');

            // The multi-return has to be the LAST thing on the line for its
            // extra values to survive; anything after it truncates them.
            const tail = new RegExp(`[.:\\w]${escaped}\\s*\\([^)]*\\)\\s*$`);

            if (tail.test(value)) {
                problems.push(`  ${file}:${index + 1}  returns ${call}(...) unparenthesised — wrap it: return (${value.slice(0, 48)}…)`);
                break;
            }
        }
    }
}

console.log(`check-returns — ${scanned} returns scanned across ${files.length} files`);

if (problems.length) {
    console.log(`\n${problems.length} multi-return leak(s):`);
    for (const line of problems) console.log(line);
    process.exit(1);
}

console.log('no function leaks a second return value to its caller');
