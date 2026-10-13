#!/usr/bin/env node
'use strict';

// Prints a 20-minute App Store Connect API token (JWT, ES256) for curl.
// Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (the .p8 file's contents).

const crypto = require('node:crypto');

const { ASC_KEY_ID: kid, ASC_ISSUER_ID: iss, ASC_KEY_P8: p8 } = process.env;
if (!kid || !iss || !p8) {
  console.error('Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8.');
  process.exit(1);
}

const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const body = `${encode({ alg: 'ES256', kid, typ: 'JWT' })}.${encode({ iss, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })}`;
const signature = crypto.sign('sha256', Buffer.from(body), { key: p8, dsaEncoding: 'ieee-p1363' });
process.stdout.write(`${body}.${signature.toString('base64url')}`);
