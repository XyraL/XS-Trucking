// A cheap structural pass over the Lua: balanced block keywords, balanced
// brackets and quotes, and no leftover merge markers. Not a parser — it will
// not catch a logic error — but it catches the class of typo that stops a file
// loading at all, which FiveM reports once and then carries on without.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

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

const files = ['bridge', 'shared', 'client', 'server', 'items'].flatMap(walk);
files.push('config.lua', 'fxmanifest.lua');

const problems = [];

// Strips comments and string literals so their contents cannot be counted.
function strip(src) {
    let out = '';
    let i = 0;

    while (i < src.length) {
        const two = src.slice(i, i + 2);

        if (two === '--') {
            if (src.slice(i + 2, i + 4) === '[[') {
                const end = src.indexOf(']]', i + 4);
                i = end === -1 ? src.length : end + 2;
            } else {
                const end = src.indexOf('\n', i);
                i = end === -1 ? src.length : end;
            }
            continue;
        }

        if (two === '[[') {
            const end = src.indexOf(']]', i + 2);
            out += ' ';
            i = end === -1 ? src.length : end + 2;
            continue;
        }

        const ch = src[i];

        if (ch === '"' || ch === "'") {
            i += 1;
            while (i < src.length && src[i] !== ch) {
                if (src[i] === '\\') i += 1;
                i += 1;
            }
            i += 1;
            out += ' ';
            continue;
        }

        out += ch;
        i += 1;
    }

    return out;
}

for (const file of files) {
    const full = path.join(ROOT, file);
    if (!existsSync(full)) continue;

    const raw = readFileSync(full, 'utf8');

    if (/^(<<<<<<<|>>>>>>>|=======)$/m.test(raw)) {
        problems.push(`${file}: merge conflict markers`);
    }

    const src = strip(raw);

    let depth = 0;
    const opens = src.match(/\b(function|if|for|while|do)\b/g) || [];
    const ends = src.match(/\bend\b/g) || [];

    // `for`/`while` each carry their own `do`, so those pair up and must not be
    // counted twice.
    const dos = (src.match(/\bdo\b/g) || []).length;
    const loops = (src.match(/\b(for|while)\b/g) || []).length;
    const blocks = opens.length - Math.min(dos, loops);

    if (blocks !== ends.length) {
        problems.push(`${file}: ${blocks} block opener(s) vs ${ends.length} end(s)`);
    }

    for (const [open, close, label] of [['{', '}', 'brace'], ['(', ')', 'paren'], ['[', ']', 'bracket']]) {
        const a = (src.split(open).length - 1);
        const b = (src.split(close).length - 1);
        if (a !== b) problems.push(`${file}: unbalanced ${label}s (${a} vs ${b})`);
    }
}

if (problems.length) {
    console.log('check-lua FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-lua ok — ${files.length} files`);
