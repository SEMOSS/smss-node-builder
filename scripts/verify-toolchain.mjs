import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

// Check the actual installed distributions, including nested bundled copies.
// http-cache-semantics 4.3.0 is outside the reported affected range; the
// upstream advisory remains disputed and this check is not proof of a fix.
const minimums = {
  npm: '11.21.0',
  pnpm: '11.28.5',
  'brace-expansion': '5.0.11',
  'http-cache-semantics': '4.3.0',
  'ip-address': '10.3.1',
  tar: '7.5.21',
};
const found = new Set();
const globalRoot = resolve(process.argv[2] || '/usr/local/lib/node_modules');

function atLeast(version, minimum) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) return false;
  const actual = version.split('.').map(Number);
  const required = minimum.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if (actual[i] !== required[i]) return actual[i] > required[i];
  }
  return true;
}

function inspect(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      inspect(path);
    } else if (entry.isFile() && entry.name === 'package.json') {
      const { name, version } = JSON.parse(readFileSync(path, 'utf8'));
      if (!Object.hasOwn(minimums, name)) continue;
      if (!atLeast(version, minimums[name])) {
        throw new Error(`${path}: ${name}@${version} is below ${minimums[name]}`);
      }
      found.add(name);
      console.log(`${name}@${version}: ${path}`);
    }
  }
}

inspect(join(globalRoot, 'npm'));
inspect(join(globalRoot, 'pnpm'));
for (const name of Object.keys(minimums)) {
  if (!found.has(name)) throw new Error(`Toolchain package was not verified: ${name}`);
}
