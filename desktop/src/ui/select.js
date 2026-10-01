'use strict';

// Click a paragraph to hear it. Ctrl/Shift-click or drag across to pick several,
// then press Enter or the button. Esc or right-click cancels.

const $ = (id) => document.getElementById(id);
let state = { action: 'tldr', paragraphs: [] };
const picked = new Set();
let drag = null;

window.notchman.onSelect((next) => {
  if (next.image) {
    $('shot').src = next.image;
    picked.clear();
    document.body.classList.remove('ready');
    $('boxes').replaceChildren();
  }
  state = { ...state, ...next };
  render();
});

function verb() {
  return state.action === 'tldr' ? 'TL;DR' : 'hear';
}

function render() {
  if (!state.paragraphs || state.phase === 'reading') {
    $('hintText').textContent = 'Finding paragraphs…';
    $('go').classList.add('hidden');
    return;
  }
  document.body.classList.add('ready');
  if (!state.paragraphs.length) {
    $('hintText').textContent = 'No readable paragraphs on this screen.';
    return;
  }
  if (!$('boxes').children.length) {
    $('boxes').replaceChildren(...state.paragraphs.map((p, i) => {
      const box = document.createElement('div');
      box.className = 'para';
      box.dataset.id = String(p.id);
      const pad = 6;
      Object.assign(box.style, {
        left: `${p.x - pad}px`, top: `${p.y - pad}px`, width: `${p.width + pad * 2}px`, height: `${p.height + pad * 2}px`,
        animationDelay: `${Math.min(i * 18, 260)}ms`,
      });
      const badge = document.createElement('span');
      badge.className = 'badge';
      box.append(badge);
      return box;
    }));
  }
  let n = 0;
  for (const box of $('boxes').children) {
    const on = picked.has(Number(box.dataset.id));
    box.classList.toggle('picked', on);
    if (on) box.querySelector('.badge').textContent = String(++n);
  }
  if (picked.size > 1) {
    $('hintText').textContent = `${picked.size} paragraphs picked`;
    $('go').textContent = state.action === 'tldr' ? 'TL;DR them' : 'Read them';
    $('go').classList.remove('hidden');
  } else {
    $('hintText').textContent = `Click a paragraph to ${verb()} it · Ctrl-click or drag for several`;
    $('go').classList.add('hidden');
  }
}

function send(ids) {
  if (!ids.length) return;
  window.notchman.select('pick', ids);
}

$('boxes').addEventListener('click', (event) => {
  const box = event.target.closest('.para');
  if (!box || drag?.moved) return;
  const id = Number(box.dataset.id);
  if (event.ctrlKey || event.shiftKey || event.metaKey) {
    if (picked.has(id)) picked.delete(id); else picked.add(id);
    render();
  } else if (picked.size > 1) {
    send([...picked]);
  } else {
    send([id]);
  }
});

window.addEventListener('mousedown', (event) => {
  if (event.button !== 0 || event.target.closest('.hint')) return;
  drag = { x: event.clientX, y: event.clientY, moved: false };
});

window.addEventListener('mousemove', (event) => {
  if (!drag) return;
  const w = event.clientX - drag.x;
  const h = event.clientY - drag.y;
  if (Math.abs(w) + Math.abs(h) < 8) return;
  drag.moved = true;
  const rect = { x: Math.min(drag.x, event.clientX), y: Math.min(drag.y, event.clientY), width: Math.abs(w), height: Math.abs(h) };
  Object.assign($('drag').style, { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px` });
  $('drag').classList.remove('hidden');
  picked.clear();
  for (const p of state.paragraphs || []) {
    if (p.x < rect.x + rect.width && p.x + p.width > rect.x && p.y < rect.y + rect.height && p.y + p.height > rect.y) picked.add(p.id);
  }
  render();
});

window.addEventListener('mouseup', () => {
  if (!drag) return;
  const wasDrag = drag.moved;
  $('drag').classList.add('hidden');
  setTimeout(() => { drag = null; }, 0);
  // A drag that caught one paragraph plays it straight away; several wait for the button.
  if (wasDrag && picked.size === 1) send([...picked]);
});

$('go').addEventListener('click', () => send([...picked]));
$('cancel').addEventListener('click', () => window.notchman.select('cancel'));
window.addEventListener('contextmenu', (event) => { event.preventDefault(); window.notchman.select('cancel'); });
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') window.notchman.select('cancel');
  if (event.key === 'Enter' && picked.size) send([...picked]);
});
