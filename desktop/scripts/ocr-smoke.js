'use strict';

// Checks the OS's built-in text recognition on a test image (run by CI on
// Windows and Mac): node scripts/ocr-smoke.js
const fs = require('node:fs');
const path = require('node:path');
const nativeOcr = require('../src/native-ocr');
const { paragraphs } = require('../src/core/paragraphs');

(async () => {
  const png = fs.readFileSync(path.join(__dirname, '../test/fixtures/screen-text.png'));
  const width = png.readUInt32BE(16);
  const height = png.readUInt32BE(20);
  let started = Date.now();
  console.log('warm up:', await nativeOcr.warmUp(), `${Date.now() - started} ms`);
  for (let run = 1; run <= 2; run++) {
    started = Date.now();
    const lines = await nativeOcr.readLines(png, width, height);
    console.log(`run ${run}: ${lines.length} lines in ${Date.now() - started} ms`);
    for (const l of lines) console.log(' ', Math.round(l.x), Math.round(l.y), Math.round(l.width), Math.round(l.height), l.confidence, l.text);
    const found = paragraphs(lines);
    console.log(`  ${found.length} paragraphs`);
    if (!lines.some((l) => /Notchman/i.test(l.text))) throw new Error('Expected text not recognised');
  }
  process.exit(0);
})().catch((error) => {
  console.error('FAILED:', error);
  process.exit(1);
});
