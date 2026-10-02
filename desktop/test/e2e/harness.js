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

const CHAT = `<html><body style="margin:0;font:18px/1.5 Arial;background:#f4f6fb;color:#111">
<div style="display:flex;height:100vh"><div style="width:260px;background:#202123;color:#ddd;padding:20px">New chat<br><br>Pricing ideas<br>Launch plan</div>
<div style="flex:1;padding:40px 120px">
<p style="background:#fff;border-radius:16px;padding:16px 20px;max-width:640px;margin-left:auto">Should we launch the beta on Friday or wait for the new onboarding to be ready next month?</p>
<p style="max-width:820px">Launching on Friday is reasonable if the core flow works, because early feedback is worth more than polish. The risk is that the current onboarding loses about a third of new users before they reach their first result, so you would be measuring the onboarding problem rather than the product.</p>
<p style="max-width:820px">A middle path is to launch on Friday to a small group of 50 users you can talk to directly, fix the two biggest onboarding drop-off points during the next two weeks, and open the beta widely once day-7 retention is above 30 percent.</p>
<p style="max-width:820px">Whatever you choose, set up basic analytics before launch, otherwise you will not know which change made the difference.</p>
</div></div></body></html>`;

const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    log.push(`${req.method} ${req.url} install=${req.headers['x-notchman-install'] ? 'yes' : 'no'} ${body.slice(0, 80)}`);
    if (req.url === '/chat') {
      res.setHeader('Content-Type', 'text/html');
      return res.end(CHAT);
    }
    if (req.url === '/article') {
      res.setHeader('Content-Type', 'text/html');
      return res.end(ARTICLE);
    }
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/tldr') return res.end(JSON.stringify({ summary: 'Your interview moved to Friday at 11. Confirm attendance tonight and bring your portfolio.' }));
    if (req.url === '/speak' && process.env.FAIL_VOICE) { res.statusCode = 503; return res.end(JSON.stringify({ code: 'unavailable', message: "The voice couldn't be made." })); }
    if (req.url === '/speak') return setTimeout(() => res.end(JSON.stringify({ audio, audioFormat: 'mp3' })), 300);
    res.statusCode = 404;
    res.end('{}');
  });
});

server.listen(0, '127.0.0.1', () => {
  const base = `http://127.0.0.1:${server.address().port}`;
  process.env.NOTCHMAN_API_URL = base;
  app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'notchman-e2e-')));
  const { run, openSettings, startPicker } = require('../../src/main.js');

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
    // The floating Shiba and its menu.
    const find = (name) => BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes(name));
    const buddyWin = find('buddy.html');
    log.push(`buddy visible=${buddyWin?.isVisible()} bounds=${JSON.stringify(buddyWin?.getBounds())}`);
    fs.writeFileSync(path.join(out, '7-buddy.png'), (await buddyWin.webContents.capturePage()).toPNG());
    buddyWin.webContents.send('buddy', { open: true, side: 'left' });
    const { ipcMain } = require('electron');
    ipcMain.emit('buddy', {}, 'open');
    await wait(600);
    fs.writeFileSync(path.join(out, '8-buddy-menu.png'), (await buddyWin.webContents.capturePage()).toPNG());
    log.push(`buddy open bounds=${JSON.stringify(buddyWin.getBounds())}`);
    ipcMain.emit('buddy', {}, 'close');

    // A page with text behind, then the paragraph picker over it.
    const page = new BrowserWindow({ x: 0, y: 0, width: 1920, height: 1080, show: true, frame: false });
    await page.loadURL(`${base}/chat`);
    await wait(800);
    const started = Date.now();
    startPicker('tldr');
    await wait(1200);
    const pickerWin = find('select.html');
    fs.writeFileSync(path.join(out, '9-picker-reading.png'), (await pickerWin.webContents.capturePage()).toPNG());
    let boxes = 0;
    for (let i = 0; i < 40 && !boxes; i++) {
      await wait(500);
      boxes = await pickerWin.webContents.executeJavaScript("document.querySelectorAll('.para').length");
    }
    log.push(`picker found ${boxes} paragraphs in ${Date.now() - started} ms`);
    await wait(700);
    await pickerWin.webContents.executeJavaScript("document.querySelectorAll('.para')[1]?.dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); document.querySelectorAll('.para')[2]?.classList.add('picked'); 1");
    fs.writeFileSync(path.join(out, '10-picker-ready.png'), (await pickerWin.webContents.capturePage()).toPNG());
    await pickerWin.webContents.executeJavaScript("document.querySelectorAll('.para')[2]?.click(); 1");
    await wait(2500);
    log.push(`after pick: picker visible=${pickerWin.isVisible()} buddy visible=${buddyWin.isVisible()}`);
    await shot('11-picked-playing');
    page.destroy();

    openSettings();
    await wait(1500);
    const settingsWindow = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes('settings.html'));
    fs.writeFileSync(path.join(out, '6-settings.png'), (await settingsWindow.webContents.capturePage()).toPNG());
    fs.writeFileSync(path.join(out, 'log.txt'), log.join('\n'));
    app.exit(0);
  });
});
