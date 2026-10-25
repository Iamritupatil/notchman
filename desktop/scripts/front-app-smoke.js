'use strict';

// Checks reading the icon of the app in front, the way a TL;DR does, on a real
// Mac (CI): npx electron scripts/front-app-smoke.js
// With --old it tries Electron's app.getFileIcon instead, which crashes the
// app on some macOS versions (that's why the Mac doesn't use it).
const { app } = require('electron');
const frontApp = require('../src/front-app');

const APP = '/System/Applications/Calculator.app';

app.whenReady().then(async () => {
  try {
    if (process.argv.includes('--old')) {
      const icon = await app.getFileIcon(APP, { size: 'large' });
      console.log(`app.getFileIcon: ${icon.isEmpty() ? 'empty' : 'ok'} (no crash on this Mac)`);
      app.exit(0);
      return;
    }
    let started = Date.now();
    const icon = await frontApp.macAppIcon(APP);
    console.log(`Calculator icon: ${icon ? `${icon.length} characters` : 'none'} in ${Date.now() - started} ms`);
    if (!icon || !icon.startsWith('data:image/png;base64,')) throw new Error('No icon for Calculator');
    started = Date.now();
    const front = await frontApp.frontAppIcon(app);
    console.log(`app in front: ${front ? 'icon' : 'no icon'} in ${Date.now() - started} ms`);
    app.exit(0);
  } catch (error) {
    console.error(error);
    app.exit(1);
  }
});
