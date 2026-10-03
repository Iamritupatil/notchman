'use strict';

// Checks the free on-computer voice (Kokoro) end to end in Electron (CI runs
// it on Windows and Mac): npx electron scripts/kokoro-smoke.js
const { app } = require('electron');
const localVoice = require('../src/local-voice');

app.on('web-contents-created', (_e, contents) => {
  contents.on('console-message', (event) => console.log('[voice page]', event.message));
});

app.whenReady().then(async () => {
  try {
    let started = Date.now();
    const first = await localVoice.speak('Notchman reads your copied post out loud.');
    console.log(`first (includes the model download): ${first.length} bytes in ${Date.now() - started} ms`);
    const text = 'Your interview moved to Friday at eleven. Confirm attendance tonight, and bring your portfolio. The panel has three people from the design team.';
    started = Date.now();
    const second = await localVoice.speak(text);
    const seconds = (second.length - 44) / 2 / 24000;
    console.log(`second: ${second.length} bytes (${seconds.toFixed(1)} s of speech) in ${Date.now() - started} ms`);
    started = Date.now();
    const short = await localVoice.speak('Here is the short version.');
    console.log(`short first piece: ${((short.length - 44) / 2 / 24000).toFixed(1)} s of speech in ${Date.now() - started} ms`);
    if (first.length < 10000 || second.length < 10000) throw new Error('Audio too short');
    app.exit(0);
  } catch (error) {
    console.error('FAILED:', error);
    app.exit(1);
  }
});
