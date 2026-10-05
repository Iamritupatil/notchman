'use strict';

// A one-way hash of the computer's own ID (Windows MachineGuid, Mac hardware
// UUID). It stays the same after a reinstall, so the server can count free
// limits per computer. The real ID never leaves the computer, and the hash is
// salted for Notchman, so it can't be matched with other apps' identifiers.

const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

function machineId() {
  try {
    if (process.platform === 'win32') {
      const out = execFileSync('reg', ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'],
        { encoding: 'utf8', timeout: 3000, windowsHide: true });
      return out.match(/MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)/)?.[1];
    }
    if (process.platform === 'darwin') {
      const out = execFileSync('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice'], { encoding: 'utf8', timeout: 3000 });
      return out.match(/"IOPlatformUUID"\s*=\s*"([^"]+)"/)?.[1];
    }
  } catch {
    // No ID: the server counts per install instead.
  }
  return undefined;
}

let cached;

/** 64 hex characters, or undefined if the computer's ID can't be read. */
function deviceId() {
  if (cached === undefined) {
    const id = machineId();
    cached = id ? crypto.createHash('sha256').update(`notchman-device:${id.toLowerCase()}`).digest('hex') : null;
  }
  return cached || undefined;
}

module.exports = { deviceId };
