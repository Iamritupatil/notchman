'use strict';

// Kokoro, the free voice that runs on this computer (see ui/voice.js). Used
// when the cloud voice (ElevenLabs) isn't available. Needs the app to be ready.

const path = require('node:path');
const { BrowserWindow, ipcMain } = require('electron');

const DEFAULT_VOICE = 'af_heart';
/** The first time includes downloading the model. */
const TIMEOUT_MS = 180000;

let win = null;
let ready = null;
let counter = 0;
const pending = new Map();

ipcMain.on('kokoro:answer', (_event, { id, wav, error }) => {
  const request = pending.get(id);
  if (!request) return;
  pending.delete(id);
  clearTimeout(request.timer);
  if (error || !wav) request.reject(new Error(error || 'No audio'));
  else request.resolve(Buffer.from(wav));
});

function engine() {
  if (win && !win.isDestroyed()) return ready;
  win = new BrowserWindow({
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'ui', 'voice-preload.js'),
      contextIsolation: true,
      backgroundThrottling: false,
    },
  });
  ready = new Promise((resolve) => ipcMain.once('kokoro:ready', resolve));
  win.loadFile(path.join(__dirname, 'ui', 'voice.html'));
  win.on('closed', () => {
    win = null;
    for (const [id, request] of pending) {
      pending.delete(id);
      request.reject(new Error('Voice engine closed'));
    }
  });
  return ready;
}

/** Starts loading the model in the background. */
async function warmUp() {
  await engine();
  win?.webContents.send('kokoro:warm');
}

/**
 * WAV audio of `text` in a Kokoro voice.
 * @returns {Promise<Buffer>}
 */
async function speak(text, voice = DEFAULT_VOICE) {
  await engine();
  const id = ++counter;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error('The computer voice took too long'));
    }, TIMEOUT_MS);
    pending.set(id, { resolve, reject, timer });
    win.webContents.send('kokoro:speak', { id, text, voice });
  });
}

module.exports = { speak, warmUp, DEFAULT_VOICE };
