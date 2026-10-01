'use strict';

// Notchman for Windows and Mac.
//
// Copy anything (a message, an answer, a link) in any app, press Alt+T, and
// the TL;DR plays from a small pill at the top of the screen. Alt+R reads it in
// full. The app you're in keeps focus; Notchman lives in the tray / menu bar.

const path = require('node:path');
const fs = require('node:fs');
const {
  app, BrowserWindow, Tray, Menu, clipboard, globalShortcut, ipcMain, screen, nativeImage, shell, Notification,
} = require('electron');
const config = require('./config');
const { createSettingsStore } = require('./settings-store');
const { createClient } = require('./core/api');
const { createPipeline, NothingToRead, hash } = require('./core/pipeline');
const links = require('./core/links');
const { standaloneURL } = require('./core/input');

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => openSettings());
}

const isMac = process.platform === 'darwin';
const asset = (name) => path.join(__dirname, '..', 'assets', name);

let settings;
let api;
let pipeline;
let tray = null;
let pill = null;
let settingsWindow = null;
let pillReady = Promise.resolve();

// What's loaded in the pill: one "session" per press.
let session = null;
let sessionCounter = 0;
const audioCache = new Map(); // `${voiceId}:${hash(piece)}` → Buffer
let voiceDirectory;

// ---------------------------------------------------------------------------
// Startup

app.whenReady().then(() => {
  if (isMac) app.dock?.hide();
  settings = createSettingsStore(app.getPath('userData'));
  voiceDirectory = path.join(app.getPath('userData'), 'voice');
  api = createClient({ baseURL: config.apiURL, installId: settings.get('installId') });
  pipeline = createPipeline({
    resolve: (url) => links.resolve(url, { render: renderPage }),
    summarize: (text) => api.tldr(text),
  });

  createTray();
  createPill();
  registerShortcuts();
  app.setLoginItemSettings({ openAtLogin: Boolean(settings.get('openAtLogin')) });

  if (settings.isFirstRun) {
    settings.set({ welcomed: true });
    // The first thing a new user sees is how to use it, not a setup flow.
    showMessage(`Copy any message or link, then press ${pretty(settings.get('tldrShortcut'))}.`, 9000);
  }
});

app.on('window-all-closed', (event) => event.preventDefault()); // keep running in the tray
app.on('will-quit', () => globalShortcut.unregisterAll());

// ---------------------------------------------------------------------------
// Shortcuts

function registerShortcuts() {
  globalShortcut.unregisterAll();
  const failed = [];
  for (const [action, key] of [['tldr', settings.get('tldrShortcut')], ['read', settings.get('readShortcut')]]) {
    const ok = key && globalShortcut.register(key, () => run(action));
    if (!ok) failed.push(pretty(key));
  }
  if (failed.length) {
    showMessage(`${failed.join(' and ')} is used by another app. Pick a different shortcut in Settings.`, 9000);
  }
}

function pretty(accelerator) {
  if (!accelerator) return '';
  return accelerator
    .replace('CommandOrControl', isMac ? '⌘' : 'Ctrl')
    .replace('Alt', isMac ? '⌥' : 'Alt')
    .replace('Shift', isMac ? '⇧' : 'Shift')
    .replace(/\+/g, isMac ? '' : '+');
}

// ---------------------------------------------------------------------------
// The flow: clipboard → (fetch) → (summarize) → voice → play

async function run(action, copiedOverride) {
  const copied = copiedOverride ?? await readClipboard();
  const id = ++sessionCounter;
  session = { id, action, pieces: [], original: null };
  showPill();
  sendState({ kind: 'working', id, action, status: 'Getting content…' });

  try {
    const prepared = await pipeline.prepare(copied, action, (stage) => {
      if (id !== session?.id) return;
      const url = standaloneURL(copied);
      const status = stage === 'fetching'
        ? (url && links.isPostSource(links.sourceName(url)) ? 'Fetching post…' : 'Fetching page…')
        : 'Summarizing…';
      sendState({ kind: 'working', id, action, status });
    });
    if (id !== session?.id) return; // a newer press replaced this one
    session = { id, action, pieces: prepared.pieces, original: prepared.original, source: prepared.source, title: prepared.title };
    sendState({ kind: 'working', id, action, status: 'Generating voice…', title: prepared.title, source: prepared.source });
    sendState({
      kind: 'play', id, action, title: prepared.title, source: prepared.source,
      pieceCount: prepared.pieces.length, speed: settings.get('speed'), canReadOriginal: action === 'tldr',
      // Listening times at ~150 words a minute, so the time saved is visible.
      spokenWords: wordCount(prepared.spoken), originalWords: wordCount(prepared.original),
    });
  } catch (error) {
    if (id !== session?.id) return;
    sendState({ kind: 'error', id, message: friendly(error) });
  }
}

function wordCount(text) {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function friendly(error) {
  if (error instanceof NothingToRead || error instanceof links.LinkError) return error.message;
  if (error && error.name === 'ApiError') return error.message;
  return "Couldn't do that. Check your connection.";
}

/** What's on the clipboard: plain text, or the text of copied HTML. */
async function readClipboard() {
  // Newer Electron versions return clipboard reads as promises.
  const text = await clipboard.readText();
  if (typeof text === 'string' && text.trim()) return text;
  const html = await clipboard.readHTML();
  if (typeof html === 'string' && html) return html.replace(/<(br|\/p|\/div|\/li|\/h\d)[^>]*>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ');
  return '';
}

/** Audio for one piece, voiced with its neighbours as context; cached on disk. */
async function pieceAudio(id, index) {
  if (!session || session.id !== id) return null;
  const pieces = session.pieces;
  const text = pieces[index];
  if (!text) return null;
  const voiceId = settings.get('voiceId');
  const key = `${voiceId}-${hash(text)}`;
  if (audioCache.has(key)) return audioCache.get(key);
  const file = path.join(voiceDirectory, `${key}.mp3`);
  try {
    const saved = fs.readFileSync(file);
    audioCache.set(key, saved);
    return saved;
  } catch { /* not saved yet */ }
  const audio = await api.speak({
    text, voiceId, previousText: pieces[index - 1], nextText: pieces[index + 1],
  });
  audioCache.set(key, audio);
  if (audioCache.size > 200) audioCache.delete(audioCache.keys().next().value);
  try {
    fs.mkdirSync(voiceDirectory, { recursive: true });
    fs.writeFileSync(file, audio);
  } catch { /* cache is optional */ }
  return audio;
}

/** Loads a page in a hidden browser window, for pages built with JavaScript. */
async function renderPage(url) {
  const win = new BrowserWindow({ show: false, width: 1200, height: 900, webPreferences: { offscreen: true, javascript: true, partition: 'render' } });
  try {
    await Promise.race([win.loadURL(url), new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 15000))]);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    return await win.webContents.executeJavaScript('document.documentElement.outerHTML');
  } finally {
    win.destroy();
  }
}

// ---------------------------------------------------------------------------
// The pill

const PILL = { width: 460, height: 72 };

function createPill() {
  pill = new BrowserWindow({
    width: PILL.width,
    height: PILL.height,
    show: false,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    hasShadow: false,
    // The app you're in keeps focus: the pill never takes the keyboard.
    focusable: false,
    alwaysOnTop: true,
    ...(isMac ? { type: 'panel' } : {}),
    webPreferences: {
      preload: path.join(__dirname, 'ui', 'preload.js'),
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false,
      autoplayPolicy: 'no-user-gesture-required',
    },
  });
  pill.setAlwaysOnTop(true, 'screen-saver');
  if (isMac) pill.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  pillReady = new Promise((resolve) => pill.webContents.once('did-finish-load', resolve));
  pill.loadFile(path.join(__dirname, 'ui', 'pill.html'));
}

function showPill() {
  if (!pill) return;
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const { x, y, width } = display.bounds;
  pill.setBounds({ x: Math.round(x + (width - PILL.width) / 2), y: y + (isMac ? 4 : 8), ...PILL });
  pill.showInactive();
}

function hidePill() {
  pill?.hide();
}

function sendState(state) {
  // States sent before the pill has loaded (the first-run welcome) wait for it.
  pillReady.then(() => pill?.webContents.send('state', state));
}

function showMessage(message, ms = 5000) {
  showPill();
  sendState({ kind: 'message', id: ++sessionCounter, message, hideAfter: ms });
}

ipcMain.handle('piece', (_event, id, index) => pieceAudio(id, index).catch((error) => {
  if (session?.id === id) sendState({ kind: 'error', id, message: friendly(error) });
  return null;
}));

ipcMain.on('control', (_event, command) => {
  switch (command) {
    case 'hide':
      hidePill();
      break;
    case 'stop':
      session = null;
      hidePill();
      break;
    case 'original':
      // The full original, from what's already fetched: no new download.
      if (session?.original) run('read', session.original);
      break;
    case 'settings':
      openSettings();
      break;
    default:
      break;
  }
});

// ---------------------------------------------------------------------------
// Tray and settings

function createTray() {
  const image = nativeImage.createFromPath(asset(isMac ? 'tray.png' : 'tray@2x.png'));
  if (isMac) image.setTemplateImage(false);
  tray = new Tray(image.resize({ width: 16, height: 16 }));
  tray.setToolTip('Notchman');
  const menu = () => Menu.buildFromTemplate([
    { label: `TL;DR what I copied   ${pretty(settings.get('tldrShortcut'))}`, click: () => run('tldr') },
    { label: `Read what I copied   ${pretty(settings.get('readShortcut'))}`, click: () => run('read') },
    { type: 'separator' },
    { label: 'Settings…', click: openSettings },
    { label: 'Website', click: () => shell.openExternal('https://notchman.app') },
    { type: 'separator' },
    { label: 'Quit Notchman', click: () => app.quit() },
  ]);
  tray.setContextMenu(menu());
  tray.on('click', () => tray.popUpContextMenu(menu()));
}

function openSettings() {
  if (settingsWindow) {
    settingsWindow.show();
    settingsWindow.focus();
    return;
  }
  settingsWindow = new BrowserWindow({
    width: 440,
    height: 820,
    resizable: false,
    title: 'Notchman Settings',
    icon: asset('icon.png'),
    autoHideMenuBar: true,
    backgroundColor: '#c4e4fa',
    webPreferences: { preload: path.join(__dirname, 'ui', 'preload.js'), contextIsolation: true, sandbox: true },
  });
  settingsWindow.loadFile(path.join(__dirname, 'ui', 'settings.html'));
  settingsWindow.on('closed', () => { settingsWindow = null; });
}

ipcMain.handle('settings:get', () => ({
  settings: settings.all(),
  voices: config.voices,
  shortcutChoices: config.shortcutChoices,
  platform: process.platform,
  version: app.getVersion(),
}));

ipcMain.handle('settings:set', (_event, changes) => {
  const allowed = {};
  if (config.voices.some((v) => v.id === changes.voiceId)) allowed.voiceId = changes.voiceId;
  if ([0.75, 1, 1.25, 1.5, 1.75, 2].includes(changes.speed)) allowed.speed = changes.speed;
  if (config.shortcutChoices.tldr.includes(changes.tldrShortcut)) allowed.tldrShortcut = changes.tldrShortcut;
  if (config.shortcutChoices.read.includes(changes.readShortcut)) allowed.readShortcut = changes.readShortcut;
  if (typeof changes.openAtLogin === 'boolean') allowed.openAtLogin = changes.openAtLogin;
  const updated = settings.set(allowed);
  if ('tldrShortcut' in allowed || 'readShortcut' in allowed) registerShortcuts();
  if ('openAtLogin' in allowed) app.setLoginItemSettings({ openAtLogin: allowed.openAtLogin });
  if ('speed' in allowed) sendState({ kind: 'speed', speed: allowed.speed });
  if (tray) createTrayMenuRefresh();
  return updated;
});

function createTrayMenuRefresh() {
  tray.destroy();
  createTray();
}

ipcMain.handle('voice:preview', async (_event, voiceId) => {
  if (!config.voices.some((v) => v.id === voiceId)) return null;
  try {
    return await api.speak({ text: "Hi, I'm your Notchman voice. Copy anything and I'll tell you what matters.", voiceId });
  } catch (error) {
    if (Notification.isSupported()) new Notification({ title: 'Notchman', body: friendly(error) }).show();
    return null;
  }
});

// For the end-to-end test harness (test/e2e).
module.exports = { run, openSettings };
