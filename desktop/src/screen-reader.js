'use strict';

// Reads the text on screen so the user can pick a paragraph: a screenshot of
// the display (Windows needs no permission; Mac asks once for Screen
// Recording), then on-device text recognition (Tesseract, English). Nothing
// leaves the computer at this step.
//
// Speed: the screenshot is read at its own resolution (enlarging it barely
// helps and costs ~40%), split into horizontal strips that several workers
// read at the same time.

const os = require('node:os');
const path = require('node:path');
const { paragraphs, linesFromWords } = require('./core/paragraphs');

/** Workers reading in parallel: a few, leaving a core for the rest of the computer. */
const WORKERS = Math.max(1, Math.min(4, (os.cpus()?.length || 2) - 1));
/** Strips overlap by this much, so every line lies whole inside one strip. */
const OVERLAP = 80;

let poolPromise = null;
let next = 0;

/** Paths inside a packaged app point into app.asar; the OCR files are unpacked next to it. */
function unpacked(p) {
  return p.replace(`app.asar${path.sep}`, `app.asar.unpacked${path.sep}`);
}

function createOne(cachePath) {
  const { createWorker } = require('tesseract.js');
  // The LSTM-only "best_int" model: smaller (3 MB vs 11 MB) and made for OEM 1.
  const langPath = unpacked(path.dirname(require.resolve('@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz')));
  return createWorker('eng', 1, {
    langPath,
    cachePath,
    gzip: true,
    workerPath: unpacked(require.resolve('tesseract.js/src/worker-script/node/index.js')),
    corePath: unpacked(path.dirname(require.resolve('tesseract.js-core/package.json'))),
  });
}

function pool(cachePath) {
  if (!poolPromise) {
    poolPromise = Promise.all(Array.from({ length: WORKERS }, () => createOne(cachePath))).catch((error) => {
      poolPromise = null;
      throw error;
    });
  }
  return poolPromise;
}

/** Starts the OCR workers in the background so the first pick is fast. */
function warmUp(cachePath) {
  pool(cachePath).catch(() => {});
}

/**
 * Recognized text lines in an image, in the image's pixels.
 * @param {Buffer} png
 * @returns {Promise<{text, x, y, width, height, confidence}[]>}
 */
async function readLines(png, cachePath) {
  const workers = await pool(cachePath);
  const worker = workers[next++ % workers.length];
  const { data } = await worker.recognize(png, {}, { blocks: true, text: false, hocr: false, tsv: false });
  const words = [];
  for (const block of data.blocks || []) {
    for (const paragraph of block.paragraphs || []) {
      for (const line of paragraph.lines || []) {
        for (const word of line.words || []) {
          const { x0, y0, x1, y1 } = word.bbox;
          // Word boxes vary with ascenders; the line's height is steadier.
          const lineHeight = line.bbox.y1 - line.bbox.y0;
          words.push({ text: word.text, x: x0, y: line.bbox.y0, width: x1 - x0, height: lineHeight || (y1 - y0), confidence: word.confidence });
        }
      }
    }
  }
  return linesFromWords(words);
}

/**
 * Horizontal strips covering `height`: each has a core band (a line belongs
 * to the strip whose core holds its centre) and is read with OVERLAP above
 * and below, so lines crossing a core edge are still read whole.
 */
function strips(height, count) {
  const core = Math.ceil(height / count);
  const result = [];
  for (let i = 0; i < count; i++) {
    const coreStart = i * core;
    const coreEnd = Math.min(height, coreStart + core);
    if (coreStart >= coreEnd) break;
    const y = Math.max(0, coreStart - OVERLAP);
    result.push({ y, height: Math.min(height, coreEnd + OVERLAP) - y, coreStart, coreEnd });
  }
  return result;
}

/**
 * Paragraphs on a screenshot, in the display's coordinates (what the overlay uses).
 * @param {Electron.NativeImage} image screenshot in physical pixels
 * @param {number} scaleFactor display scale (physical pixels per point)
 */
async function findParagraphs(image, scaleFactor, cachePath) {
  const { width, height } = image.getSize();
  const parts = strips(height, height > 600 ? WORKERS : 1);
  const results = await Promise.all(parts.map(async (part) => {
    const crop = parts.length > 1 ? image.crop({ x: 0, y: part.y, width, height: part.height }) : image;
    const lines = await readLines(crop.toPNG(), cachePath);
    return lines
      .map((l) => ({ ...l, y: l.y + part.y }))
      .filter((l) => {
        const centre = l.y + l.height / 2;
        return centre >= part.coreStart && centre < part.coreEnd;
      });
  }));
  const toPoints = 1 / scaleFactor;
  const scaled = results.flat().map((l) => ({
    ...l, x: l.x * toPoints, y: l.y * toPoints, width: l.width * toPoints, height: l.height * toPoints,
  }));
  return paragraphs(scaled);
}

module.exports = { findParagraphs, readLines, warmUp, strips };
