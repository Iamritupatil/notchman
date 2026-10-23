'use strict';

// The app you're using when you ask Notchman to listen (Chrome, WhatsApp,
// Word, Slack…), so the pill can show that app's own icon. Read at the moment
// of the press, before Notchman's own windows show. Nothing is stored or sent.
//
// Windows: the program behind the window in front (a small PowerShell call).
// Mac: the frontmost application (osascript).

const path = require('node:path');
const { execFile } = require('node:child_process');

const WINDOWS_SCRIPT = `
Add-Type @"
using System; using System.Runtime.InteropServices;
public class NotchmanFront {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
"@
$pid0 = 0
[void][NotchmanFront]::GetWindowThreadProcessId([NotchmanFront]::GetForegroundWindow(), [ref]$pid0)
(Get-Process -Id $pid0).Path
`;

function run(file, args) {
  return new Promise((resolve) => {
    execFile(file, args, { windowsHide: true, timeout: 4000 }, (error, stdout) => resolve(error ? '' : String(stdout).trim()));
  });
}

/** The path of the app in front, or null. */
async function frontAppPath() {
  if (process.platform === 'win32') {
    const found = await run('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', WINDOWS_SCRIPT]);
    return found && /\.exe$/i.test(found) ? found : null;
  }
  if (process.platform === 'darwin') {
    const found = await run('osascript', ['-e', 'POSIX path of (path to frontmost application)']);
    return found ? found.replace(/\/$/, '') : null;
  }
  return null;
}

/**
 * The icon of the app in front, as a PNG data URL, or null (Notchman itself,
 * the desktop, or when it can't be read).
 * @param {Electron.App} app
 */
async function frontAppIcon(app) {
  try {
    const found = await frontAppPath();
    if (!found) return null;
    const name = path.basename(found).toLowerCase();
    if (name.startsWith('notchman') || name === 'explorer.exe' || name === 'finder.app' || found === process.execPath) return null;
    // Never wait long for an icon: the pill goes on without it.
    const icon = await Promise.race([
      app.getFileIcon(found, { size: 'large' }),
      new Promise((resolve) => setTimeout(() => resolve(null), 2000)),
    ]);
    return icon && !icon.isEmpty() ? icon.toDataURL() : null;
  } catch {
    return null;
  }
}

module.exports = { frontAppIcon };
