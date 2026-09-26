// Formats the files lint-staged passes in, each with the Prettier of the
// package it belongs to. packages/web-app is on Svelte 5 and needs its own
// prettier-plugin-svelte and compiler; the root install resolves Svelte 4
// (through the sip-test-tools-ui workspace), which cannot parse runes or
// snippets.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const webApp = path.join(root, 'packages', 'web-app');
const files = process.argv.slice(2).map((f) => path.resolve(root, f));
const inWebApp = (f) => f.startsWith(webApp + path.sep);

function prettier(dir, targets) {
  if (targets.length === 0) return;
  const bin = path.join(dir, 'node_modules', '.bin', 'prettier');
  if (!existsSync(bin)) {
    console.error(`${bin} is missing: run npm install in ${path.relative(root, dir) || '.'}`);
    process.exit(1);
  }
  execFileSync(bin, ['--write', ...targets], { stdio: 'inherit', cwd: dir });
}

prettier(webApp, files.filter(inWebApp));
prettier(root, files.filter((f) => !inWebApp(f)));
