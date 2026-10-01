'use strict';

// Reads the text on screen so the user can pick a paragraph: a screenshot of
// the display (Windows needs no permission; Mac asks once for Screen
// Recording), then on-device text recognition (Tesseract, English). Nothing
// leaves the computer at this step.

const path = require('node:path');
const { paragraphs, linesFromWords } = require('./core/paragraphs');

let workerPromise = null;

/** Paths inside a packaged app point into app.asar; the OCR files are unpacked next to it. */
function unpacked(p) {
  return p.replace(`app.asar${path.sep}`, `app.asar.unpacked${path.sep}`);
}

function ocrWorker(cachePath) {
  if (!workerPromise) {
    const { createWorker } = require('tesseract.js');
    const langPath = unpacked(path.dirname(require.resolve('@tesseract.js-data/eng/4.0.0/eng.traineddata.gz')));
    workerPromise = createWorker('eng', 1, {
      langPath,
      cachePath,
      gzip: true,
      workerPath: unpacked(require.resolve('tesseract.js/src/worker-script/node/index.js')),
      corePath: unpacked(path.dirname(require.resolve('tesseract.js-core/package.json'))),
    }).catch((error) => {
      workerPromise = null;
      throw error;
    });
  }
  return workerPromise;
}

/** Starts the OCR engine in the background so the first pick is fast. */
function warmUp(cachePath) {
  ocrWorker(cachePath).catch(() => {});
}

/**
 * Recognized text lines in an image, in the image's pixels.
 * @param {Buffer} png
 * @returns {Promise<{text, x, y, width, height, confidence}[]>}
 */
async function readLines(png, cachePath) {
  const worker = await ocrWorker(cachePath);
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
 * Paragraphs on a screenshot, in the display's coordinates (what the overlay uses).
 * Small text is enlarged first: recognition is much more accurate on it.
 * @param {Electron.NativeImage} image screenshot in physical pixels
 * @param {number} scaleFactor display scale (physical pixels per point)
 */
async function findParagraphs(image, scaleFactor, cachePath) {
  const { width } = image.getSize();
  const upscale = scaleFactor >= 1.75 ? 1 : Math.min(2, 2 / scaleFactor);
  const source = upscale > 1 ? image.resize({ width: Math.round(width * upscale), quality: 'best' }) : image;
  const lines = await readLines(source.toPNG(), cachePath);
  const toPoints = 1 / (upscale * scaleFactor);
  const scaled = lines.map((l) => ({
    ...l, x: l.x * toPoints, y: l.y * toPoints, width: l.width * toPoints, height: l.height * toPoints,
  }));
  return paragraphs(scaled);
}

module.exports = { findParagraphs, readLines, warmUp };
