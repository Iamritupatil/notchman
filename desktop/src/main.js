'use strict';

// Notchman for Windows and Mac.
//
// Two ways in:
//  - The floating Shiba: drag it anywhere; click it, choose TL;DR or Read, and
//    every paragraph on screen gets a liquid-glass outline. Click one (or
//    several) and it plays.
//  - Copy anything (a message, an answer, a link) and press Alt+T (TL;DR) or
//    Alt+R (Read).
// The TL;DR plays from a small pill at the top of the screen; the app you're
// in keeps focus. Notchman also lives in the tray / menu bar.

const path = require('node:path');
const fs = require('node:fs');
const {
  app, BrowserWindow, Tray, Menu, clipboard, globalShortcut, ipcMain, screen, nativeImage, shell, Notification, desktopCapturer,
} = require('electron');
const config = require('./config');

// A failure in a background helper (text recognition, a voice request) must
// never pop up Electron's "JavaScript error" dialog: log it and keep running.
process.on('uncaughtException', (error) => console.error('uncaught', error));
process.on('unhandledRejection', (error) => console.error('unhandled', error));
const { createSettingsStore } = require('./settings-store');
const { createClient } = require('./core/api');
const { createPipeline, NothingToRead, hash } = require('./core/pipeline');
const links = require('./core/links');
const { standaloneURL } = require('./core/input');
const { joinParagraphs } = require('./core/paragraphs');
const screenReader = require('./screen-reader');
const localVoice = require('./local-voice');
const selection = require('./selection');

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
let buddy = null;
let trayMenu = null;
let picker = null;

// What's loaded in the pill: one "session" per press.
let session = null;
let sessionCounter = 0;
const audioCache = new Map(); // `${voiceId}:${hash(piece)}` → Buffer
let voiceDirectory;

// ---------------------------------------------------------------------------
// Startup

// `--self-test=<png> --self-test-out=<file>`: checks screen reading (both
// recognizers) and the computer voice inside the packaged app, writes the
// results to the file and quits. CI runs it on the built Windows and Mac apps.
const selfTestArg = process.argv.find((a) => a.startsWith('--self-test='));

async function runSelfTest() {
  const outArg = process.argv.find((a) => a.startsWith('--self-test-out='));
  const out = outArg ? outArg.slice('--self-test-out='.length) : path.join(app.getPath('temp'), 'notchman-self-test.txt');
  const lines = [];
  const log = (line) => { lines.push(line); fs.writeFileSync(out, lines.join('\n')); };
  const step = async (name, fn) => {
    const started = Date.now();
    try {
      log(`${name}: ok ${await fn()} (${Date.now() - started} ms)`);
    } catch (error) {
      log(`${name}: FAILED ${error?.stack || error} (${Date.now() - started} ms)`);
    }
  };
  log(`version ${app.getVersion()} ${process.platform} ${process.arch}`);
  const image = nativeImage.createFromPath(selfTestArg.slice('--self-test='.length));
  const cache = path.join(app.getPath('userData'), 'ocr');
  await step('built-in OCR', async () => (await screenReader.findParagraphs(image, 1, cache)).length + ' paragraphs');
  await step('Tesseract OCR', async () => (await screenReader.findParagraphs(image, 1, cache, { native: false })).length + ' paragraphs');
  await step('Kokoro voice', async () => (await localVoice.speak('Notchman reads your copied post out loud.')).length + ' bytes');
  log('done');
  app.exit(0);
}

app.whenReady().then(() => {
  if (selfTestArg) return runSelfTest();
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
  createPicker();
  if (settings.get('showBuddy') !== false) createBuddy();
  registerShortcuts();
  app.setLoginItemSettings({ openAtLogin: Boolean(settings.get('openAtLogin')) });
  // Start the text recognizer in the background so the first pick is quick.
  screenReader.warmUp(path.join(app.getPath('userData'), 'ocr'));
  selection.warmUp();

  if (settings.isFirstRun) {
    settings.set({ welcomed: true });
    // The first thing a new user sees is how to use it, not a setup flow.
    showMessage(`Click the Shiba to TL;DR anything on screen, or copy text and press ${pretty(settings.get('tldrShortcut'))}.`, 10000);
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

async function run(action, copiedOverride, { source } = {}) {
  const copied = copiedOverride ?? await readClipboard();
  const id = ++sessionCounter;
  session = { id, action, pieces: [], original: null };
  showPill();
  sendState({ kind: 'working', id, action, status: 'Getting content…' });
  buddyState({ busy: true, speaking: false });

  try {
    const prepared = await pipeline.prepare(copied, action, (stage) => {
      if (id !== session?.id) return;
      const url = standaloneURL(copied);
      const status = stage === 'fetching'
        ? (url && links.isPostSource(links.sourceName(url)) ? 'Fetching post…' : 'Fetching page…')
        : 'Summarizing…';
      sendState({ kind: 'working', id, action, status });
    }, { source });
    if (id !== session?.id) return; // a newer press replaced this one
    const pieces = usingLocalVoice() || action === 'read' ? smallPieces(prepared.spoken) : prepared.pieces;
    session = { id, action, pieces, original: prepared.original, source: prepared.source, title: prepared.title };
    sendState({ kind: 'working', id, action, status: 'Generating voice…', title: prepared.title, source: prepared.source });
    sendState({
      kind: 'play', id, action, title: prepared.title, source: prepared.source,
      pieceCount: pieces.length, speed: settings.get('speed'), canReadOriginal: action === 'tldr',
      // Listening times at ~150 words a minute, so the time saved is visible.
      spokenWords: wordCount(prepared.spoken), originalWords: wordCount(prepared.original),
    });
    buddyState({ busy: false, speaking: true });
  } catch (error) {
    if (id !== session?.id) return;
    buddyState({ busy: false, speaking: false });
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

// Voices, best first: the cloud voice (ElevenLabs), then Kokoro, a free open
// voice that runs on this computer, then the system voice (read by the pill).
// For a while after the cloud voice fails, pieces skip it.
const CLOUD_VOICE_RETRY_MS = 30 * 60 * 1000;
const voiceStateFile = () => path.join(app.getPath('userData'), 'voice-state.json');
let cloudVoiceFailedAt = (() => {
  try { return Number(JSON.parse(fs.readFileSync(voiceStateFile(), 'utf8')).cloudVoiceFailedAt) || 0; } catch { return 0; }
})();
function markCloudVoiceFailed() {
  cloudVoiceFailedAt = Date.now();
  try { fs.writeFileSync(voiceStateFile(), JSON.stringify({ cloudVoiceFailedAt })); } catch { /* optional */ }
}
const usingLocalVoice = () => Date.now() - cloudVoiceFailedAt < CLOUD_VOICE_RETRY_MS;

/**
 * Pieces for the computer voice: a sentence or two each (the first one short),
 * so speech starts within seconds and the next piece is made while one plays.
 */
function smallPieces(text) {
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'sentence' });
  const pieces = [];
  let current = '';
  for (const { segment } of segmenter.segment(text)) {
    const limit = pieces.length === 0 ? 90 : 240;
    if (current && current.length + segment.length > limit) {
      pieces.push(current.trim());
      current = '';
    }
    current += segment;
  }
  if (current.trim()) pieces.push(current.trim());
  return pieces.filter(Boolean);
}
const kokoroCache = new Map(); // hash(piece) → WAV Buffer

async function kokoroAudio(text) {
  const key = hash(text);
  if (kokoroCache.has(key)) return kokoroCache.get(key);
  const audio = await localVoice.speak(text);
  kokoroCache.set(key, audio);
  if (kokoroCache.size > 100) kokoroCache.delete(kokoroCache.keys().next().value);
  return audio;
}

ipcMain.handle('piece', async (_event, id, index) => {
  const text = session?.id === id ? session.pieces[index] : null;
  if (!text) return null;
  // Full reads are long: they use the free voice so the cloud voice's credits
  // go to TL;DRs.
  if (!usingLocalVoice() && session.action !== 'read') {
    try {
      return { audio: await pieceAudio(id, index), type: 'audio/mpeg' };
    } catch (error) {
      console.error('cloud voice failed, using the computer voice', error);
      markCloudVoiceFailed();
    }
  }
  try {
    return { audio: await kokoroAudio(text), type: 'audio/wav' };
  } catch (error) {
    console.error('Kokoro failed, using the system voice', error);
    return { speak: text };
  }
});

ipcMain.on('control', (_event, command) => {
  switch (command) {
    case 'hide':
      hidePill();
      buddyState({ speaking: false, busy: false });
      break;
    case 'stop':
      session = null;
      hidePill();
      buddyState({ speaking: false, busy: false });
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
// The floating Shiba

const BUDDY = { width: 88, height: 82, menuWidth: 186, openHeight: 138 };
let buddyOpen = false;
let buddyLook = { busy: false, speaking: false, valign: 'center' };
let dragTimer = null;

function createBuddy() {
  const saved = settings.get('buddyPosition');
  const area = screen.getPrimaryDisplay().workArea;
  const start = saved && screen.getAllDisplays().some((d) => inside(saved, d.workArea))
    ? saved
    : { x: area.x + area.width - BUDDY.width - 24, y: area.y + Math.round(area.height * 0.62) };
  buddy = new BrowserWindow({
    x: start.x, y: start.y, width: BUDDY.width, height: BUDDY.height,
    frame: false, transparent: true, resizable: false, maximizable: false, minimizable: false, fullscreenable: false,
    skipTaskbar: true, hasShadow: false, alwaysOnTop: true,
    // Clicking the Shiba doesn't take focus from the app you're in.
    focusable: false,
    ...(isMac ? { type: 'panel' } : {}),
    webPreferences: { preload: path.join(__dirname, 'ui', 'preload.js'), contextIsolation: true, sandbox: true },
  });
  buddy.setAlwaysOnTop(true, 'screen-saver');
  if (isMac) buddy.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  buddy.loadFile(path.join(__dirname, 'ui', 'buddy.html'));
  buddy.once('ready-to-show', () => buddy.showInactive());
  buddy.on('closed', () => { buddy = null; });
}

function inside(point, rect) {
  return point.x >= rect.x - 40 && point.y >= rect.y - 40 && point.x < rect.x + rect.width && point.y < rect.y + rect.height;
}

/** Where the Shiba itself is (the window grows sideways when the menu opens). */
function shibaPosition() {
  const b = buddy.getBounds();
  if (!buddyOpen) return { x: b.x, y: b.y };
  const extra = BUDDY.openHeight - BUDDY.height;
  const dy = buddyLook.valign === 'top' ? 0 : buddyLook.valign === 'bottom' ? extra : Math.round(extra / 2);
  return { x: buddyLook.side === 'left' ? b.x + b.width - BUDDY.width : b.x, y: b.y + dy };
}

function setBuddyOpen(open) {
  if (!buddy) return;
  const shiba = shibaPosition();
  buddyOpen = open;
  if (open) {
    const area = screen.getDisplayNearestPoint(shiba).workArea;
    const roomRight = area.x + area.width - (shiba.x + BUDDY.width);
    const side = roomRight >= BUDDY.menuWidth + 8 ? 'right' : 'left';
    const width = BUDDY.width + BUDDY.menuWidth;
    // The Shiba stays exactly where it is; the menu is centred on it, or
    // aligned to its top / bottom near a screen edge, so nothing goes off screen.
    const extra = BUDDY.openHeight - BUDDY.height;
    let y = shiba.y - Math.round(extra / 2);
    let valign = 'center';
    if (y < area.y) { y = shiba.y; valign = 'top'; }
    else if (y + BUDDY.openHeight > area.y + area.height) { y = shiba.y - extra; valign = 'bottom'; }
    buddy.setBounds({ x: side === 'right' ? shiba.x : shiba.x - BUDDY.menuWidth, y, width, height: BUDDY.openHeight });
    buddyLook.side = side;
    buddyLook.valign = valign;
  } else {
    buddy.setBounds({ x: shiba.x, y: shiba.y, width: BUDDY.width, height: BUDDY.height });
    buddyLook.side = 'right';
    buddyLook.valign = 'center';
  }
  buddyState({});
}

function buddyState(changes) {
  buddyLook = { ...buddyLook, ...changes };
  buddy?.webContents.send('buddy', { ...buddyLook, open: buddyOpen });
}

ipcMain.on('buddy', (_event, command) => {
  if (!buddy) return;
  switch (command) {
    case 'drag-start': {
      if (buddyOpen) setBuddyOpen(false);
      const cursor = screen.getCursorScreenPoint();
      const start = buddy.getBounds();
      const offset = { x: cursor.x - start.x, y: cursor.y - start.y };
      clearInterval(dragTimer);
      dragTimer = setInterval(() => {
        const point = screen.getCursorScreenPoint();
        buddy?.setPosition(point.x - offset.x, point.y - offset.y);
      }, 12);
      break;
    }
    case 'drag-end':
      clearInterval(dragTimer);
      dragTimer = null;
      settings.set({ buddyPosition: shibaPosition() });
      break;
    case 'open':
      setBuddyOpen(true);
      break;
    case 'close':
      setBuddyOpen(false);
      break;
    case 'tldr':
    case 'read':
      setBuddyOpen(false);
      listenToSelection(command);
      break;
    case 'pick':
      setBuddyOpen(false);
      startPicker('tldr');
      break;
    case 'menu':
      if (tray && trayMenu) tray.popUpContextMenu(trayMenu());
      break;
    default:
      break;
  }
});

/**
 * TL;DR or Read from the Shiba: the text selected in the app you're using
 * (copied for you, no screenshot), or what you copied if nothing is selected.
 */
async function listenToSelection(action) {
  let selected = '';
  try {
    selected = await selection.selectedText(clipboard);
  } catch {
    selected = '';
  }
  if (selected) return run(action, selected, { source: 'Selected text' });
  return run(action);
}

// ---------------------------------------------------------------------------
// The paragraph picker

let pickerState = null;

function createPicker() {
  picker = new BrowserWindow({
    show: false, frame: false, transparent: false, resizable: false, movable: false, skipTaskbar: true,
    hasShadow: false, alwaysOnTop: true, fullscreenable: false, backgroundColor: '#000000',
    ...(isMac ? { type: 'panel' } : {}),
    webPreferences: { preload: path.join(__dirname, 'ui', 'preload.js'), contextIsolation: true, sandbox: true },
  });
  picker.setAlwaysOnTop(true, 'screen-saver');
  picker.loadFile(path.join(__dirname, 'ui', 'select.html'));
  picker.on('closed', () => { picker = null; });
}

/** Screenshot of a display, at its full resolution. */
async function captureDisplay(display) {
  const size = { width: Math.round(display.size.width * display.scaleFactor), height: Math.round(display.size.height * display.scaleFactor) };
  const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: size });
  const source = sources.find((s) => s.display_id === String(display.id)) || sources[0];
  if (!source || source.thumbnail.isEmpty()) throw new Error('capture failed');
  return source.thumbnail;
}

async function startPicker(action) {
  if (!picker || pickerState) return;
  const anchor = buddy ? shibaPosition() : screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(anchor);
  // Notchman's own windows stay out of the screenshot.
  const hadPill = pill?.isVisible();
  buddy?.hide();
  if (hadPill) pill.hide();
  await new Promise((resolve) => setTimeout(resolve, 140));

  let image;
  try {
    image = await captureDisplay(display);
  } catch {
    buddy?.showInactive();
    if (hadPill) pill.showInactive();
    showMessage(isMac
      ? 'Notchman needs Screen Recording permission: System Settings → Privacy & Security → Screen Recording.'
      : "Couldn't see the screen. Try again.", 8000);
    return;
  }
  const token = Symbol('pick');
  pickerState = { token, action, paragraphs: null, hadPill };
  picker.setBounds(display.bounds);
  picker.webContents.send('select', { image: image.toDataURL(), action, phase: 'reading', paragraphs: null });
  picker.show();
  picker.focus();

  try {
    const found = await screenReader.findParagraphs(image, display.scaleFactor, path.join(app.getPath('userData'), 'ocr'));
    if (pickerState?.token !== token) return;
    pickerState.paragraphs = found;
    picker.webContents.send('select', { phase: 'ready', paragraphs: found });
  } catch (error) {
    console.error('screen reading failed', error);
    if (pickerState?.token !== token) return;
    pickerState.paragraphs = [];
    picker.webContents.send('select', { phase: 'ready', paragraphs: [] });
  }
}

function closePicker() {
  const state = pickerState;
  pickerState = null;
  picker?.hide();
  buddy?.showInactive();
  if (state?.hadPill && session) pill?.showInactive();
}

ipcMain.on('select', (_event, command, ids) => {
  if (!pickerState) return;
  if (command === 'cancel') {
    closePicker();
    return;
  }
  if (command === 'pick' && Array.isArray(ids)) {
    const chosen = (pickerState.paragraphs || []).filter((p) => ids.includes(p.id));
    const { action } = pickerState;
    closePicker();
    if (chosen.length) run(action, joinParagraphs(chosen), { source: 'On screen' });
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
    { label: 'TL;DR a paragraph on screen…', click: () => startPicker('tldr') },
    { label: `TL;DR what I copied   ${pretty(settings.get('tldrShortcut'))}`, click: () => run('tldr') },
    { label: `Read what I copied   ${pretty(settings.get('readShortcut'))}`, click: () => run('read') },
    { type: 'separator' },
    {
      label: 'Show the Shiba', type: 'checkbox', checked: Boolean(buddy),
      click: (item) => {
        settings.set({ showBuddy: item.checked });
        if (item.checked && !buddy) createBuddy();
        if (!item.checked && buddy) buddy.close();
      },
    },
    { label: 'Settings…', click: openSettings },
    { label: 'Website', click: () => shell.openExternal('https://notchman.app') },
    { type: 'separator' },
    { label: `Notchman ${app.getVersion()}`, enabled: false },
    { label: 'Quit Notchman', click: () => app.quit() },
  ]);
  tray.setContextMenu(menu());
  tray.on('click', () => tray.popUpContextMenu(menu()));
  trayMenu = menu;
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
module.exports = { run, openSettings, startPicker };
