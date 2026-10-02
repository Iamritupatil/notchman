'use strict';

// The text recognition built into the operating system: Windows.Media.Ocr on
// Windows, Apple's Vision on Mac. Both run on the computer, are tuned for
// screen text, and take well under a second for a whole screen, so the picker
// uses them first and only falls back to Tesseract if they aren't available.
//
// Windows: one PowerShell process stays open; it reads an image path per line
// on stdin and answers with one line of JSON. Mac: osascript runs a small
// JavaScript-for-Automation script that calls Vision.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFile } = require('node:child_process');

const isWindows = process.platform === 'win32';
const isMac = process.platform === 'darwin';

/** Longest we wait for one screen before giving up and using Tesseract. */
const TIMEOUT_MS = 10000;

const WINDOWS_SCRIPT = String.raw`
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation${'`'}1'
  })[0]
  function Await($operation, [Type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($operation))
    $task.Wait(-1) | Out-Null
    $task.Result
  }
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  if ($null -eq $engine) { throw 'No Windows text recognition language is installed.' }
  [Console]::Out.WriteLine('{"ready":true}')
} catch {
  [Console]::Out.WriteLine((ConvertTo-Json -Compress @{ error = "$_" }))
  exit 1
}
[Console]::Out.Flush()
while ($true) {
  $imagePath = [Console]::In.ReadLine()
  if ($null -eq $imagePath) { break }
  try {
    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($imagePath)) ([Windows.Storage.StorageFile])
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $out = New-Object System.Text.StringBuilder
    [void]$out.Append('{"lines":[')
    $first = $true
    foreach ($line in $result.Lines) {
      $x0 = [double]::MaxValue; $y0 = [double]::MaxValue; $x1 = 0.0; $y1 = 0.0
      foreach ($word in $line.Words) {
        $r = $word.BoundingRect
        if ($r.X -lt $x0) { $x0 = $r.X }
        if ($r.Y -lt $y0) { $y0 = $r.Y }
        if ($r.X + $r.Width -gt $x1) { $x1 = $r.X + $r.Width }
        if ($r.Y + $r.Height -gt $y1) { $y1 = $r.Y + $r.Height }
      }
      if ($x1 -le 0) { continue }
      if (-not $first) { [void]$out.Append(',') }
      $first = $false
      [void]$out.Append((ConvertTo-Json -Compress @{ t = $line.Text; x = $x0; y = $y0; w = ($x1 - $x0); h = ($y1 - $y0) }))
    }
    [void]$out.Append(']}')
    $stream.Dispose()
    [Console]::Out.WriteLine($out.ToString())
  } catch {
    [Console]::Out.WriteLine((ConvertTo-Json -Compress @{ error = "$_" }))
  }
  [Console]::Out.Flush()
}
`;

// Vision's boxes are 0–1 with the origin at the bottom left.
const MAC_SCRIPT = `
ObjC.import('Foundation');
ObjC.import('Vision');
function run(argv) {
  const url = $.NSURL.fileURLWithPath(argv[0]);
  const request = $.VNRecognizeTextRequest.alloc.init;
  request.recognitionLevel = 0;
  request.usesLanguageCorrection = true;
  const handler = $.VNImageRequestHandler.alloc.initWithURLOptions(url, $.NSDictionary.dictionary);
  const error = $();
  if (!handler.performRequestsError($.NSArray.arrayWithObject(request), error)) {
    return JSON.stringify({ error: 'Vision could not read the image.' });
  }
  const results = request.results;
  const lines = [];
  for (let i = 0; i < results.count; i++) {
    const observation = results.objectAtIndex(i);
    const candidate = observation.topCandidates(1).firstObject;
    if (!candidate) continue;
    const box = observation.boundingBox;
    lines.push({ t: candidate.string.js, c: candidate.confidence, x: box.origin.x, y: box.origin.y, w: box.size.width, h: box.size.height });
  }
  return JSON.stringify({ lines: lines, normalized: true });
}
`;

const scratch = path.join(os.tmpdir(), 'notchman-ocr');

function scriptFile(name, contents) {
  fs.mkdirSync(scratch, { recursive: true });
  const file = path.join(scratch, name);
  fs.writeFileSync(file, contents);
  return file;
}

/**
 * The OS's answer as picker lines, in the image's pixels (top-left origin).
 * @param {{lines?: object[], normalized?: boolean, error?: string}} reply
 */
function toLines(reply, width, height) {
  if (!reply || reply.error) throw new Error(reply?.error || 'No reply');
  const list = Array.isArray(reply.lines) ? reply.lines : reply.lines ? [reply.lines] : [];
  return list
    .filter((l) => l && typeof l.t === 'string' && l.t.trim())
    .map((l) => {
      const confidence = typeof l.c === 'number' ? Math.round(l.c * 100) : 100;
      if (reply.normalized) {
        return {
          text: l.t, confidence,
          x: l.x * width, y: (1 - l.y - l.h) * height, width: l.w * width, height: l.h * height,
        };
      }
      return { text: l.t, confidence, x: l.x, y: l.y, width: l.w, height: l.h };
    });
}

// MARK: Windows

let windows = null;

function windowsProcess() {
  if (windows) return windows;
  const child = spawn('powershell.exe',
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptFile('ocr.ps1', WINDOWS_SCRIPT)],
    { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
  const state = { child, waiting: [], buffer: '', ready: null };
  state.ready = new Promise((resolve, reject) => state.waiting.push({ resolve, reject }));
  state.ready.catch(() => {});
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    state.buffer += chunk;
    let newline;
    while ((newline = state.buffer.indexOf('\n')) >= 0) {
      const line = state.buffer.slice(0, newline).trim();
      state.buffer = state.buffer.slice(newline + 1);
      if (!line) continue;
      const next = state.waiting.shift();
      if (!next) continue;
      try {
        const reply = JSON.parse(line);
        if (reply.error) next.reject(new Error(reply.error));
        else next.resolve(reply);
      } catch (error) {
        next.reject(error);
      }
    }
  });
  const fail = () => {
    if (windows === state) windows = null;
    for (const next of state.waiting.splice(0)) next.reject(new Error('Windows text recognition stopped'));
  };
  child.on('exit', fail);
  child.on('error', fail);
  windows = state;
  return state;
}

async function windowsRead(file) {
  const state = windowsProcess();
  await state.ready;
  return new Promise((resolve, reject) => {
    state.waiting.push({ resolve, reject });
    state.child.stdin.write(`${file}\n`);
  });
}

// MARK: Mac

let macScript = null;

function macRead(file) {
  macScript ??= scriptFile('ocr.js', MAC_SCRIPT);
  return new Promise((resolve, reject) => {
    execFile('osascript', ['-l', 'JavaScript', macScript, file], { timeout: TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024 },
      (error, stdout) => {
        if (error) return reject(error);
        try { resolve(JSON.parse(stdout)); } catch (e) { reject(e); }
      });
  });
}

// MARK: Public

const available = isWindows || isMac;
let broken = !available;
let counter = 0;

function withTimeout(promise) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Text recognition took too long')), TIMEOUT_MS); }),
  ]).finally(() => clearTimeout(timer));
}

/**
 * Text lines in a PNG, in its pixels. Rejects if the OS can't do it (then use Tesseract).
 * @param {Buffer} png
 */
async function readLines(png, width, height) {
  if (broken) throw new Error('Built-in text recognition is unavailable');
  fs.mkdirSync(scratch, { recursive: true });
  const file = path.join(scratch, `screen-${process.pid}-${counter++ % 4}.png`);
  fs.writeFileSync(file, png);
  try {
    const reply = await withTimeout(isWindows ? windowsRead(file) : macRead(file));
    return toLines(reply, width, height);
  } catch (error) {
    // Couldn't start at all: don't try again this session.
    if (isWindows && !windows) broken = true;
    throw error;
  } finally {
    fs.rm(file, { force: true }, () => {});
  }
}

/** Starts Windows' recognizer in the background. Resolves false if the OS one can't be used. */
async function warmUp() {
  if (!available) return false;
  if (isMac) return true;
  try {
    await withTimeout(windowsProcess().ready);
    return true;
  } catch {
    broken = true;
    return false;
  }
}

module.exports = { readLines, warmUp, toLines, isAvailable: () => !broken };
