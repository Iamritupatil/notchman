'use strict';

// Groups text lines read from a screenshot into paragraphs you can pick: a
// chat bubble, an answer's paragraph, a post. Layout only (vertical rhythm and
// horizontal alignment), so it's pure and unit-tested. Same idea as the
// iPhone app's MessageBlockDetector.
//
// A line: { text, x, y, width, height, confidence } in screen pixels (top-left origin).

const DEFAULTS = {
  /** Paragraphs shorter than this aren't worth listening to (buttons, names, times). */
  minimumCharacters: 25,
  /** Lines the OCR wasn't sure about (0–100). */
  minimumConfidence: 45,
};

function paragraphs(lines, options = {}) {
  const opts = { ...DEFAULTS, ...options };
  const content = lines
    .filter((l) => l && typeof l.text === 'string' && l.text.trim().length > 0)
    .filter((l) => (l.confidence ?? 100) >= opts.minimumConfidence)
    .map((l) => ({ ...l, text: l.text.trim() }))
    .sort((a, b) => (a.y !== b.y ? a.y - b.y : a.x - b.x));

  // 1. Lines that sit together (same column, close below each other) form a block.
  const groups = [];
  for (const line of content) {
    let target = -1;
    for (let i = groups.length - 1; i >= 0; i--) {
      if (belongs(line, groups[i])) { target = i; break; }
    }
    if (target >= 0) groups[target].push(line);
    else groups.push([line]);
  }

  // 2. A clearly bigger gap inside a block starts a new paragraph.
  const result = [];
  for (const group of groups) {
    let current = [];
    for (const line of group) {
      const last = current[current.length - 1];
      if (last && line.y - (last.y + last.height) > Math.max(last.height, line.height) * 0.9) {
        result.push(current);
        current = [];
      }
      current.push(line);
    }
    if (current.length) result.push(current);
  }

  return result
    .map((group, index) => toParagraph(group, index))
    .filter((p) => p.text.replace(/\s+/g, '').length >= opts.minimumCharacters);
}

function belongs(line, group) {
  const last = group[group.length - 1];
  const lineHeight = Math.max(last.height, line.height);
  const gap = line.y - (last.y + last.height);
  // Just below the previous line: within ~1.9 line heights (paragraph breaks
  // included), and not far above.
  if (gap > lineHeight * 1.9 || gap < -lineHeight * 0.5) return false;
  // Similar text size (a heading and its body, or a sidebar, stay apart).
  if (Math.max(last.height, line.height) / Math.min(last.height, line.height) > 1.6) return false;
  // Horizontally aligned with the block (same bubble / column).
  const blockLeft = Math.min(...group.map((l) => l.x));
  const overlap = Math.min(line.x + line.width, last.x + last.width) - Math.max(line.x, last.x);
  const alignedLeft = Math.abs(line.x - blockLeft) < lineHeight * 1.5;
  const overlapsEnough = overlap > Math.min(line.width, last.width) * 0.3;
  return alignedLeft || overlapsEnough;
}

function toParagraph(lines, id) {
  const left = Math.min(...lines.map((l) => l.x));
  const top = Math.min(...lines.map((l) => l.y));
  const right = Math.max(...lines.map((l) => l.x + l.width));
  const bottom = Math.max(...lines.map((l) => l.y + l.height));
  // Lines are joined into flowing text; a hyphen at a line end joins the word.
  let text = '';
  for (const line of lines) {
    if (!text) text = line.text;
    else if (/[A-Za-z]-$/.test(text)) text = text.slice(0, -1) + line.text;
    else text += ` ${line.text}`;
  }
  return { id, text, x: left, y: top, width: right - left, height: bottom - top };
}

/**
 * Builds lines from recognized words. Text recognition sometimes reads straight
 * across side-by-side columns (two cards, a sidebar and a chat); a gap much
 * wider than a space splits them back into separate lines.
 * A word: { text, x, y, width, height, confidence }.
 */
function linesFromWords(words) {
  const sorted = words
    .filter((w) => w && typeof w.text === 'string' && w.text.trim())
    .sort((a, b) => (a.y + a.height / 2) - (b.y + b.height / 2) || a.x - b.x);
  // Rows: words whose vertical centres line up.
  const rows = [];
  for (const word of sorted) {
    const centre = word.y + word.height / 2;
    const row = rows.find((r) => Math.abs(r.centre - centre) < Math.max(r.height, word.height) * 0.5);
    if (row) {
      row.words.push(word);
      row.height = Math.max(row.height, word.height);
    } else {
      rows.push({ centre, height: word.height, words: [word] });
    }
  }
  const lines = [];
  for (const row of rows) {
    const ordered = row.words.sort((a, b) => a.x - b.x);
    let current = [];
    for (const word of ordered) {
      const last = current[current.length - 1];
      // The same word read twice (overlapping boxes): keep the surer reading.
      if (last && word.x < last.x + last.width * 0.6) {
        if ((word.confidence ?? 0) > (last.confidence ?? 0)) current[current.length - 1] = word;
        continue;
      }
      if (last && word.x - (last.x + last.width) > Math.max(last.height, word.height) * 1.6) {
        lines.push(toLine(current));
        current = [];
      }
      current.push(word);
    }
    if (current.length) lines.push(toLine(current));
  }
  return lines;
}

function toLine(words) {
  const left = Math.min(...words.map((w) => w.x));
  const top = Math.min(...words.map((w) => w.y));
  const right = Math.max(...words.map((w) => w.x + w.width));
  const bottom = Math.max(...words.map((w) => w.y + w.height));
  const confidence = words.reduce((sum, w) => sum + (w.confidence ?? 100), 0) / words.length;
  return { text: words.map((w) => w.text.trim()).join(' '), x: left, y: top, width: right - left, height: bottom - top, confidence };
}

/** Text of several picked paragraphs, top to bottom. */
function joinParagraphs(picked) {
  return [...picked].sort((a, b) => (a.y !== b.y ? a.y - b.y : a.x - b.x)).map((p) => p.text).join('\n\n');
}

/** Paragraphs a dragged rectangle touches. */
function inRect(all, rect) {
  return all.filter((p) => p.x < rect.x + rect.width && p.x + p.width > rect.x
    && p.y < rect.y + rect.height && p.y + p.height > rect.y);
}

module.exports = { paragraphs, linesFromWords, joinParagraphs, inRect };
