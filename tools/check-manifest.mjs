// Asserts fxmanifest and the folder agree in both directions, plus that
// everything index.html references is listed in files{}.
//
// Catches "added a file, forgot the manifest" and the reverse. A file missing
// from the manifest is logged once at startup and then blows up somewhere
// unrelated the first time its global is touched.
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifest = readFileSync(path.join(ROOT, 'fxmanifest.lua'), 'utf8');

const problems = [];

function block(name) {
    const re = new RegExp(`${name}\\s*\\{([\\s\\S]*?)\\n\\}`, 'm');
    const found = manifest.match(re);
    if (!found) return [];

    return [...found[1].matchAll(/['"]([^'"]+)['"]/g)]
        .map((m) => m[1])
        .filter((entry) => !entry.startsWith('@'));
}

// files{} may use a single-level glob. FiveM ships nothing for a nested **,
// so that is reported rather than expanded.
const listed = new Set();

for (const entry of [...block('shared_scripts'), ...block('client_scripts'), ...block('server_scripts'), ...block('files')]) {
    if (entry.includes('**')) {
        problems.push(`nested glob ships nothing in FiveM: ${entry}`);
        continue;
    }

    if (!entry.includes('*')) {
        if (!existsSync(path.join(ROOT, entry))) problems.push(`manifest lists a file that is not on disk: ${entry}`);
        listed.add(entry);
        continue;
    }

    const dir = path.posix.dirname(entry);
    const pattern = new RegExp(`^${path.posix.basename(entry).replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*')}$`);

    if (!existsSync(path.join(ROOT, dir))) {
        problems.push(`manifest glob points at a folder that is not there: ${entry}`);
        continue;
    }

    const hits = readdirSync(path.join(ROOT, dir))
        .filter((name) => pattern.test(name) && !statSync(path.join(ROOT, dir, name)).isDirectory());

    if (!hits.length) problems.push(`manifest glob matches nothing: ${entry}`);
    for (const name of hits) listed.add(`${dir}/${name}`);
}

function walk(dir) {
    const out = [];

    for (const name of readdirSync(path.join(ROOT, dir))) {
        const rel = `${dir}/${name}`;
        if (statSync(path.join(ROOT, rel)).isDirectory()) out.push(...walk(rel));
        else out.push(rel);
    }

    return out;
}

const scripts = new Set([
    ...block('shared_scripts'),
    ...block('client_scripts'),
    ...block('server_scripts'),
]);

for (const dir of ['bridge', 'shared', 'client', 'server']) {
    if (!existsSync(path.join(ROOT, dir))) continue;

    for (const file of walk(dir)) {
        if (!file.endsWith('.lua')) continue;

        if (!listed.has(file)) {
            problems.push(`on disk but not in the manifest: ${file}`);
        } else if (!scripts.has(file)) {
            // Listed in files{} only. It ships to the client and never runs,
            // which reads exactly like a file that is simply missing.
            problems.push(`${file} is in the manifest but not in a script block, so it never loads`);
        }
    }
}

for (const file of walk('html')) {
    if (!/\.(js|css|html)$/.test(file)) continue;
    if (!listed.has(file)) problems.push(`html file not in files{}: ${file}`);
}

const index = readFileSync(path.join(ROOT, 'html/index.html'), 'utf8');
const refs = [
    ...[...index.matchAll(/src="([^"]+)"/g)].map((m) => m[1]),
    ...[...index.matchAll(/href="([^"]+)"/g)].map((m) => m[1]),
].filter((ref) => !ref.startsWith('http') && !ref.startsWith('#'));

for (const ref of refs) {
    const rel = `html/${ref.replace(/^\.\//, '')}`;

    if (!existsSync(path.join(ROOT, rel))) {
        problems.push(`index.html references a missing file: ${ref}`);
    } else if (!listed.has(rel)) {
        problems.push(`index.html references a file not in files{}: ${ref}`);
    }
}

if (problems.length) {
    console.log('check-manifest FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-manifest ok — ${listed.size} entries`);
