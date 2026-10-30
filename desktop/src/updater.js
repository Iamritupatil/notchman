'use strict';

// Updates: the newest build on the downloads site (latest.json: version
// 0.1.<build> and its installers).
//
// Windows updates itself: a new version is downloaded in the background and
// installed silently the next time Notchman starts (it starts with the
// computer), or right away from "Restart to update". Nothing to download by
// hand. Mac opens the right .dmg (silent updates there need Apple signing).
//
// latest.json is trusted only with Notchman's signature (latest.json.sig), and
// an installer only if it comes from the downloads site with the SHA-256 that
// the signed latest.json lists (core/update-check.js).

const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { app, net, shell } = require('electron');
const config = require('./config');
const { verifiedManifest, fromDownloadsSite, matchesRelease } = require('./core/update-check');

const DOWNLOAD_PAGE = 'https://notchman.app/#download';
const isWindows = process.platform === 'win32';
let cached = null;
let downloading = null;

function newer(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0);
  }
  return false;
}

const updatesDir = () => path.join(app.getPath('userData'), 'updates');
const pendingFile = () => path.join(updatesDir(), 'pending.json');

/** The downloaded update waiting to be installed: { version, file, attempts }, or null. */
function pending() {
  try {
    const value = JSON.parse(fs.readFileSync(pendingFile(), 'utf8'));
    if (value && typeof value.version === 'string' && fs.existsSync(value.file)) return value;
  } catch {
    // none
  }
  return null;
}

function clearDownloads() {
  fs.rmSync(updatesDir(), { recursive: true, force: true });
}

/** { ok, available, ready, version, current } (cached for 30 minutes unless forced). */
async function check({ force = false } = {}) {
  const current = app.getVersion();
  if (!force && cached && Date.now() - cached.at < 30 * 60_000) {
    return { ...cached.info, ready: Boolean(readyVersion(cached.info.version)) };
  }
  try {
    const base = config.downloadsURL.replace(/\/+$/, '');
    const get = async (name) => {
      const response = await net.fetch(`${base}/${name}`, { headers: { 'User-Agent': `Notchman/${current}` }, cache: 'no-store' });
      if (!response.ok) throw new Error(`downloads ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    };
    const [body, signature] = await Promise.all([get('latest.json'), get('latest.json.sig')]);
    const latest = verifiedManifest(body, signature.toString('utf8'), config.updatePublicKey);
    const version = /^\d+\.\d+\.\d+$/.test(latest.version || '') ? latest.version : null;
    // Only links to the downloads site itself are followed.
    const assets = Object.fromEntries(Object.entries(latest.files && typeof latest.files === 'object' ? latest.files : {})
      .filter(([, url]) => fromDownloadsSite(url, config.downloadsURL)));
    const hashes = latest.sha256 && typeof latest.sha256 === 'object' ? latest.sha256 : {};
    const info = { ok: true, current, version, available: Boolean(version && newer(version, current)), assets, hashes };
    cached = { at: Date.now(), info };
    return { ...info, ready: Boolean(readyVersion(version)) };
  } catch (error) {
    console.error('update check failed', error);
    return { ok: false, current, available: false, ready: false };
  }
}

function readyVersion(version) {
  const waiting = pending();
  return waiting && version && waiting.version === version ? waiting : null;
}

/**
 * Windows: downloads the installer for `info` in the background (once) and
 * keeps it for the next start. Resolves the pending update, or null.
 */
async function download(info) {
  if (!isWindows || !info?.available) return null;
  const ready = readyVersion(info.version);
  if (ready) return ready;
  const url = info.assets?.['Notchman-Setup.exe'];
  if (!url) return null;
  downloading ??= (async () => {
    try {
      const response = await net.fetch(url);
      if (!response.ok) throw new Error(`download ${response.status}`);
      const data = Buffer.from(await response.arrayBuffer());
      const sha256 = info.hashes?.['Notchman-Setup.exe'];
      if (!matchesRelease(data, sha256)) throw new Error('the download is not the released installer');
      clearDownloads();
      fs.mkdirSync(updatesDir(), { recursive: true });
      const file = path.join(updatesDir(), `Notchman-Setup-${info.version}.exe`);
      fs.writeFileSync(file, data);
      const waiting = { version: info.version, file, sha256, attempts: 0 };
      fs.writeFileSync(pendingFile(), JSON.stringify(waiting));
      return waiting;
    } catch (error) {
      console.error('update download failed', error);
      return null;
    } finally {
      downloading = null;
    }
  })();
  return downloading;
}

/** Runs the installer silently; it closes Notchman, installs and starts the new version. */
function runInstaller(waiting) {
  // Checked again right before it runs: the file must still be the released one.
  if (!matchesRelease(fs.readFileSync(waiting.file), waiting.sha256)) {
    clearDownloads();
    throw new Error('the downloaded installer changed');
  }
  waiting.attempts = (waiting.attempts || 0) + 1;
  fs.writeFileSync(pendingFile(), JSON.stringify(waiting));
  spawn(waiting.file, ['/S', '--updated', '--force-run'], { detached: true, stdio: 'ignore' }).unref();
  setTimeout(() => app.exit(0), 300);
}

/**
 * At startup (Windows): installs a downloaded update before anything opens.
 * Returns true if Notchman is quitting to update.
 */
function installPendingAtStart() {
  if (!isWindows) return false;
  const waiting = pending();
  if (!waiting) {
    if (fs.existsSync(updatesDir())) clearDownloads();
    return false;
  }
  // Already installed (or older), or it failed twice: forget it.
  if (!newer(waiting.version, app.getVersion()) || (waiting.attempts || 0) >= 2) {
    clearDownloads();
    return false;
  }
  try {
    runInstaller(waiting);
    return true;
  } catch (error) {
    console.error('update install failed', error);
    return false;
  }
}

/** Installs the newest version now. Resolves { ok, message } (on Windows the app restarts into it). */
async function install() {
  const info = await check({ force: true });
  if (!info.ok || !info.available) return { ok: false, message: info.ok ? "You're already up to date." : "Couldn't reach the update server." };
  if (isWindows) {
    const waiting = await download(info);
    if (!waiting) return { ok: false, message: "The update couldn't be downloaded. Try again later." };
    try {
      runInstaller(waiting);
      return { ok: true };
    } catch (error) {
      console.error('update install failed', error);
      return { ok: false, message: "The update couldn't be started. Try again later." };
    }
  }
  if (process.platform === 'darwin') {
    const name = process.arch === 'arm64' ? 'Notchman.dmg' : 'Notchman-Intel.dmg';
    shell.openExternal(info.assets[name] || DOWNLOAD_PAGE);
    return { ok: true, message: 'Open the download, then drag Notchman into Applications to replace this version.' };
  }
  shell.openExternal(DOWNLOAD_PAGE);
  return { ok: true };
}

module.exports = { check, download, install, installPendingAtStart };
