'use strict';

// Updates from the dashboard: the newest release on GitHub (tagged
// desktop-<build>, version 0.1.<build>). Windows downloads the installer and
// runs it (it replaces this version and restarts Notchman); Mac opens the
// right .dmg download.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { app, net, shell } = require('electron');

const REPO = 'Iamritupatil/notchman';
const RELEASES = `https://github.com/${REPO}/releases/latest`;
let cached = null;

function versionOf(tag) {
  const match = /^desktop-(\d+)$/.exec(tag || '');
  return match ? `0.1.${match[1]}` : null;
}

function newer(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0);
  }
  return false;
}

/** { ok, available, version, current } (cached for 30 minutes unless forced). */
async function check({ force = false } = {}) {
  if (!force && cached && Date.now() - cached.at < 30 * 60_000) return cached.info;
  const current = app.getVersion();
  try {
    const response = await net.fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Notchman' },
    });
    if (!response.ok) throw new Error(`GitHub ${response.status}`);
    const release = await response.json();
    const version = versionOf(release.tag_name);
    const assets = Object.fromEntries((release.assets || []).map((a) => [a.name, a.browser_download_url]));
    const info = { ok: true, current, version, available: Boolean(version && newer(version, current)), assets };
    cached = { at: Date.now(), info };
    return info;
  } catch (error) {
    console.error('update check failed', error);
    return { ok: false, current, available: false };
  }
}

/** Installs the newest version. Resolves { ok, message } (on Windows the app quits to update). */
async function install() {
  const info = await check({ force: true });
  if (!info.ok || !info.available) return { ok: false, message: info.ok ? "You're already up to date." : "Couldn't reach the update server." };
  if (process.platform === 'win32') {
    const url = info.assets['Notchman-Setup.exe'];
    if (!url) return { ok: false, message: "The update isn't ready yet. Try again in a few minutes." };
    try {
      const response = await net.fetch(url);
      if (!response.ok) throw new Error(`download ${response.status}`);
      const file = path.join(os.tmpdir(), `Notchman-Setup-${info.version}.exe`);
      fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
      // The installer closes this version, installs the new one and starts it.
      spawn(file, [], { detached: true, stdio: 'ignore' }).unref();
      setTimeout(() => app.quit(), 800);
      return { ok: true };
    } catch (error) {
      console.error('update download failed', error);
      return { ok: false, message: "The update couldn't be downloaded. Try again later." };
    }
  }
  if (process.platform === 'darwin') {
    const name = process.arch === 'arm64' ? 'Notchman.dmg' : 'Notchman-Intel.dmg';
    shell.openExternal(info.assets[name] || RELEASES);
    return { ok: true, message: 'Open the download, then drag Notchman into Applications to replace this version.' };
  }
  shell.openExternal(RELEASES);
  return { ok: true };
}

module.exports = { check, install };
