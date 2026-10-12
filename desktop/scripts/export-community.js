#!/usr/bin/env node
'use strict';

// Builds the public Notchman Community repository from this app (licensed for
// personal, non-commercial use only: PolyForm Noncommercial 1.0.0):
//   node scripts/export-community.js <out-dir>
//
// Only the files listed below are copied. Pro features (screen reading, the
// Notchman server client, payments, updates, the device ID) are left out, and
// the result is scanned for anything private before it can be published.

const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const out = path.resolve(process.argv[2] || path.join(root, 'dist', 'community'));

const FILES = [
  'assets/icon.ico', 'assets/icon.png', 'assets/shiba-face.png', 'assets/shiba.png', 'assets/mascot.png',
  'assets/tray.png', 'assets/tray@2x.png',
  'src/main.js', 'src/key-store.js', 'src/settings-store.js', 'src/history-store.js', 'src/local-voice.js', 'src/selection.js',
  'src/core/byok.js', 'src/core/input.js', 'src/core/links.js', 'src/core/pipeline.js', 'src/core/speech-text.js',
  'src/ui/buddy.css', 'src/ui/buddy.html', 'src/ui/buddy.js',
  'src/ui/pill.css', 'src/ui/pill.html', 'src/ui/pill.js',
  'src/ui/dashboard.css', 'src/ui/dashboard.html', 'src/ui/dashboard.js',
  'src/ui/theme.css', 'src/ui/icons.js', 'src/ui/settings.js', 'src/ui/preload.js',
  'src/ui/agree.html', 'src/ui/agree.css', 'src/ui/agree.js',
  'src/ui/voice.html', 'src/ui/voice.js', 'src/ui/voice-preload.js',
  'src/vendor/kokoro.web.js', 'src/vendor/kokoro-LICENSE.txt', 'src/vendor/README.md',
  'test/community.test.js',
];

// Never in the public repository (checked after copying).
const FORBIDDEN = [
  [/lambda-url\.[a-z0-9-]+\.on\.aws/i, 'the Notchman server URL'],
  [/cloudfront\.net/i, 'the downloads site'],
  [/pdt_[A-Za-z0-9]{10,}/, 'a Dodo product ID'],
  [/dodopayments\.com/i, 'Dodo Payments'],
  [/(DODO|REVENUECAT|AZURE_SPEECH|AWS)_[A-Z_]*KEY/, 'a server secret name'],
  [/\bgsk_[A-Za-z0-9]{20,}/, 'a Groq key'],
  [/\bsk_[a-f0-9]{32,}/, 'an ElevenLabs key'],
  [/AKIA[0-9A-Z]{16}/, 'an AWS key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'a private key'],
];
const PRO_FILES = ['screen-reader.js', 'native-ocr.js', 'paragraphs.js', 'updater.js', 'device-id.js', 'api.js', 'select.html', 'select.js', 'select.css'];

function copy(relative, target = relative) {
  const destination = path.join(out, target);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(path.join(root, relative), destination);
}

function write(relative, contents) {
  const destination = path.join(out, relative);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, contents);
}

// Start clean, but keep a git checkout's history (and installed packages).
fs.mkdirSync(out, { recursive: true });
for (const entry of fs.readdirSync(out)) {
  if (entry !== '.git' && entry !== 'node_modules') fs.rmSync(path.join(out, entry), { recursive: true, force: true });
}

for (const file of FILES) copy(file);
copy('community/README.md', 'README.md');
copy('community/LICENSE', 'LICENSE');
copy('community/NOTICE.md', 'NOTICE.md');
copy('community/env.example', '.env.example');
copy('community/gitignore', '.gitignore');

write('src/edition.js', `'use strict';

// Notchman Community: free for personal, non-commercial use (see LICENSE). It
// uses your own API keys and
// doesn't include the Pro features (Pick on screen, the Notchman cloud).
module.exports = { community: true };
`);

const config = require(path.join(root, 'src', 'config.js'));
write('src/config.js', `'use strict';

module.exports = ${JSON.stringify({
  voices: config.voices,
  upgradeLinks: { pro: '', proplus: '' },
  pricingPage: 'https://notchman.app',
  defaults: config.defaults,
  shortcutChoices: config.shortcutChoices,
}, null, 2)};
`);

// The core tests, without the one for the Pro server client.
const coreTests = fs.readFileSync(path.join(root, 'test', 'core.test.js'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/\ntest\('server errors keep their message for the user'[\s\S]*?\n\}\);\n?/, '\n');
if (coreTests.includes("require('../src/core/api')")) throw new Error('test/core.test.js still needs the Pro server client');
write('test/core.test.js', coreTests);

const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const build = { ...pkg.build };
build.appId = 'app.notchman.community';
build.productName = 'Notchman Community';
build.files = ['src/**/*', 'assets/**/*', 'package.json', '!**/*.{md,map,ts}'];
delete build.asarUnpack;
if (build.mac?.extendInfo) delete build.mac.extendInfo.NSScreenCaptureUsageDescription;
build.win = { ...build.win, artifactName: 'Notchman-Community-Setup.${ext}' };
build.mac = { ...build.mac, artifactName: 'Notchman-Community-${arch}.${ext}' };
build.nsis = { ...build.nsis, shortcutName: 'Notchman Community' };
write('package.json', `${JSON.stringify({
  name: 'notchman-community',
  productName: 'Notchman Community',
  version: '1.0.0',
  description: 'Copy anything, hear the TL;DR. Notchman for Windows and Mac with your own API keys. Free for personal, non-commercial use.',
  license: 'PolyForm-Noncommercial-1.0.0',
  author: 'Ritu Patil',
  homepage: 'https://notchman.app',
  main: 'src/main.js',
  scripts: {
    start: 'electron .',
    test: 'node --test test/core.test.js test/community.test.js',
    dist: 'electron-builder --win --publish never',
    'dist:mac': 'electron-builder --mac --publish never',
  },
  engines: { node: '>=20' },
  dependencies: {
    '@mozilla/readability': pkg.dependencies['@mozilla/readability'],
    linkedom: pkg.dependencies.linkedom,
  },
  devDependencies: pkg.devDependencies,
  build,
}, null, 2)}\n`);

// --- Safety checks -------------------------------------------------------------

const problems = [];
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name === 'node_modules') continue;
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) { walk(full); continue; }
    const relative = path.relative(out, full);
    if (PRO_FILES.includes(entry.name)) problems.push(`${relative}: a Pro file`);
    if (/\.(png|ico)$/.test(entry.name) || entry.name === 'kokoro.web.js') continue;
    const text = fs.readFileSync(full, 'utf8');
    for (const [pattern, what] of FORBIDDEN) {
      if (pattern.test(text)) problems.push(`${relative}: contains ${what}`);
    }
  }
}
walk(out);
// The license must stay personal, non-commercial use only.
const license = fs.readFileSync(path.join(out, 'LICENSE'), 'utf8');
if (!license.startsWith('Required Notice: Copyright') || !license.includes('PolyForm Noncommercial License 1.0.0')) {
  problems.push('LICENSE: not the PolyForm Noncommercial license with the required notice');
}
if (problems.length) {
  console.error(`Not safe to publish:\n- ${problems.join('\n- ')}`);
  process.exit(1);
}
console.log(`Notchman Community exported to ${out} (${FILES.length + 9} files), safety checks passed.`);
