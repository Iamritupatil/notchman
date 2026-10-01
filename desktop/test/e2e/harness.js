'use strict';

// Launches the real app against a fake Notchman server, presses TL;DR (copied
// text) and then TL;DR on a copied link, and screenshots the pill at each step.
// Run: xvfb-run node_modules/.bin/electron --no-sandbox test/e2e/harness.js

const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { app, clipboard, BrowserWindow } = require('electron');

const out = path.join(__dirname, 'out');
fs.mkdirSync(out, { recursive: true });
const audio = fs.readFileSync(path.join(__dirname, 'silence.wav')).toString('base64');
const log = [];

const ARTICLE = `<html><head><title>Interview update</title></head><body><nav>Home Jobs Login</nav><article><h1>Interview update</h1>${
  Array.from({ length: 6 }, (_, i) => `<p>Paragraph ${i + 1}: the panel interview moved to Friday at 11 and candidates must confirm attendance by tonight.</p>`).join('')
}</article></body></html>`;

const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    log.push(`${req.method} ${req.url} install=${req.headers['x-notchman-install'] ? 'yes' : 'no'} ${body.slice(0, 80)}`);
    if (req.url === '/article') {
      res.setHeader('Content-Type', 'text/html');
      return res.end(ARTICLE);
    }
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/tldr') return res.end(JSON.stringify({ summary: 'Your interview moved to Friday at 11. Confirm attendance tonight and bring your portfolio.' }));
    if (req.url === '/speak') return setTimeout(() => res.end(JSON.stringify({ audio, audioFormat: 'mp3' })), 300);
    res.statusCode = 404;
    res.end('{}');
  });
});

server.listen(0, '127.0.0.1', () => {
  const base = `http://127.0.0.1:${server.address().port}`;
  process.env.NOTCHMAN_API_URL = base;
  app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'notchman-e2e-')));
  const { run, openSettings } = require('../../src/main.js');

  const shot = async (name) => {
    const pill = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes('pill.html'));
    const image = await pill.webContents.capturePage();
    fs.writeFileSync(path.join(out, `${name}.png`), image.toPNG());
    log.push(`shot ${name} visible=${pill.isVisible()} bounds=${JSON.stringify(pill.getBounds())} focusable=${pill.isFocusable()}`);
  };
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  app.whenReady().then(async () => {
    await wait(1500);
    await shot('0-welcome');
    await clipboard.writeText('Hi everyone! Quick update from the hiring team. The panel interview has been moved from Thursday to Friday at 11am because two panelists are travelling. Please confirm your attendance by replying tonight, and remember to bring your portfolio. Thanks and good luck!');
    run('tldr');
    await wait(150);
    await shot('1-working');
    await wait(2500);
    await shot('2-playing');
    await clipboard.writeText(`${base}/article`);
    run('tldr');
    await wait(100);
    await shot('3-fetching');
    await wait(2500);
    await shot('4-link-playing');
    await clipboard.writeText('ok');
    run('tldr');
    await wait(400);
    await shot('5-too-short');
    openSettings();
    await wait(1500);
    const settingsWindow = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes('settings.html'));
    fs.writeFileSync(path.join(out, '6-settings.png'), (await settingsWindow.webContents.capturePage()).toPNG());
    fs.writeFileSync(path.join(out, 'log.txt'), log.join('\n'));
    app.exit(0);
  });
});
