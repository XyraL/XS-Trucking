// Does every NUI script actually parse?
//
// check-lua covers the Lua. Nothing covered the browser half, so a bad edit to
// a panel file shipped a page that threw on load and every checker still said
// yes — the panels are plain <script> tags, so one syntax error takes the whole
// page with it and the tablet opens blank.
//
// Parsed the same way the browser will: as a classic script, not a module.
//
//   node tools/check-js.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = 'html';

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) walk(path, out);
    else if (path.endsWith('.js')) out.push(path);
  }
  return out;
}

const files = walk(ROOT).sort();
const bad = [];

for (const file of files) {
  const source = readFileSync(file, 'utf8');

  try {
    // new Function compiles without running, which is the whole point: the
    // file must not execute, it must only be provably parseable.
    new Function(source);
  } catch (err) {
    bad.push({ file: relative('.', file), message: err.message });
  }
}

if (bad.length) {
  console.log('check-js FAILED');
  for (const entry of bad) console.log(`  ${entry.file}: ${entry.message}`);
  process.exit(1);
}

console.log(`check-js ok — ${files.length} script(s) parse`);
