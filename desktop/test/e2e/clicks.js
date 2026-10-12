'use strict';

// Real mouse clicks on Windows (CI): moves the actual cursor and clicks, the
// way a person does, to check the floating windows take clicks:
//  1. a message in the pill closes with its X;
//  2. clicking the Shiba opens its menu.
// Run: npx electron test/e2e/clicks.js <result-file>   (Windows only)

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { app, BrowserWindow, screen } = require('electron');

const resultFile = path.resolve(process.argv[process.argv.length - 1].endsWith('.txt') ? process.argv[process.argv.length - 1] : 'clicks.txt');
const lines = [];
const log = (line) => { lines.push(line); console.log(line); fs.writeFileSync(resultFile, `${lines.join('\n')}\n`); };
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The cursor moves and clicks through SendInput-style events (mouse_event),
// which reach the app like a real mouse.
const MOUSE = `
Add-Type -Namespace N -Name M -MemberDefinition @'
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, System.UIntPtr e);
'@
`;
function mouse(script) {
  execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', MOUSE + script], { windowsHide: true, timeout: 20000 });
}
function moveTo(point) {
  const { width, height } = screen.getPrimaryDisplay().bounds;
  const x = Math.round((point.x * 65535) / (width - 1));
  const y = Math.round((point.y * 65535) / (height - 1));
  // MOVE | ABSOLUTE, twice (a small step first so a move event surely fires).
  mouse(`[N.M]::mouse_event(0x8001, ${x - 300}, ${y}, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [N.M]::mouse_event(0x8001, ${x}, ${y}, 0, [UIntPtr]::Zero)`);
}
function click() {
  mouse('[N.M]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [N.M]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)');
}

/** Screen point of the centre of `selector` in `win`. */
async function centre(win, selector) {
  const rect = await win.webContents.executeJavaScript(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`);
  const bounds = win.getContentBounds();
  return { x: Math.round(bounds.x + rect.x), y: Math.round(bounds.y + rect.y) };
}

const find = (page) => BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes(page));

// Never the real Notchman server from a test.
process.env.NOTCHMAN_API_URL = 'http://127.0.0.1:9';
app.setPath('userData', fs.mkdtempSync(path.join(os.tmpdir(), 'notchman-clicks-')));
const { showMessage, TERMS_VERSION } = require('../../src/main.js');
fs.writeFileSync(path.join(app.getPath('userData'), 'settings.json'), JSON.stringify({ termsAccepted: TERMS_VERSION, welcomed: true }));

/** Starts counting the mouse events a window's page receives. */
const listen = (win) => win.webContents.executeJavaScript(`window.__seen = {}; for (const t of ['mousemove','pointerdown','mousedown','click']) window.addEventListener(t, () => { window.__seen[t] = (window.__seen[t] || 0) + 1; }, true); true`);
const seen = (win) => win.webContents.executeJavaScript('JSON.stringify(window.__seen || {})');

app.whenReady().then(async () => {
  let failed = false;
  try {
    await wait(4000);
    const display = screen.getPrimaryDisplay();
    log(`display ${display.bounds.width}x${display.bounds.height} scale ${display.scaleFactor}`);

    // 0. Control: an ordinary window. If this click doesn't arrive, the test
    // machine can't take simulated clicks and the results below mean nothing.
    const control = new BrowserWindow({ x: 300, y: 300, width: 300, height: 200, alwaysOnTop: true, show: true });
    await control.loadURL('data:text/html,<button id=b style="width:200px;height:100px" onclick="document.title=\'clicked\'">Click</button>');
    await wait(800);
    await listen(control);
    moveTo(await centre(control, '#b'));
    await wait(400);
    log(`cursor at ${JSON.stringify(screen.getCursorScreenPoint())}`);
    click();
    await wait(800);
    const controlOk = control.getTitle() === 'clicked';
    log(`${controlOk ? 'PASS' : 'FAIL'} control: an ordinary window takes the click (events ${await seen(control)})`);
    control.destroy();
    if (!controlOk) {
      log('RESULT: SKIPPED (this machine does not deliver simulated clicks)');
      app.exit(2);
      return;
    }

    // 1. The pill's X closes a message.
    showMessage('Testing: this message should close when its X is clicked.', 60000);
    await wait(1200);
    const pill = find('pill.html');
    await listen(pill);
    log(`pill visible before: ${pill.isVisible()} bounds ${JSON.stringify(pill.getBounds())}`);
    const x = await centre(pill, '#stop');
    moveTo(x);
    await wait(500);
    log(`cursor at ${JSON.stringify(screen.getCursorScreenPoint())}, X at ${JSON.stringify(x)}`);
    click();
    await wait(1500);
    const pillClosed = !pill.isVisible();
    log(`${pillClosed ? 'PASS' : 'FAIL'} pill X closes the message (visible after: ${pill.isVisible()}, events ${await seen(pill)})`);
    failed ||= !pillClosed;

    // 2. Clicking the Shiba opens its menu (the window widens).
    const buddy = find('buddy.html');
    await listen(buddy);
    const before = buddy.getBounds();
    const s = await centre(buddy, '#shiba');
    moveTo(s);
    await wait(500);
    click();
    await wait(1000);
    const after = buddy.getBounds();
    const opened = after.width > before.width;
    log(`${opened ? 'PASS' : 'FAIL'} clicking the Shiba opens its menu (width ${before.width} -> ${after.width}, events ${await seen(buddy)})`);
    failed ||= !opened;
  } catch (error) {
    log(`FAIL error: ${error.stack || error}`);
    failed = true;
  }
  log(failed ? 'RESULT: FAIL' : 'RESULT: PASS');
  app.exit(failed ? 1 : 0);
});
