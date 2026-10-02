'use strict';

// The floating Shiba. Press and move to drag it anywhere (the position is
// remembered); a click without moving opens TL;DR / Read.

const buddy = document.getElementById('buddy');
const shiba = document.getElementById('shiba');
let press = null;

shiba.addEventListener('mousedown', (event) => {
  if (event.button !== 0) return;
  press = { x: event.screenX, y: event.screenY, moved: false };
  window.notchman.buddy('drag-start');
});

window.addEventListener('mousemove', (event) => {
  if (!press) return;
  if (Math.abs(event.screenX - press.x) + Math.abs(event.screenY - press.y) > 4) press.moved = true;
});

window.addEventListener('mouseup', () => {
  if (!press) return;
  const wasClick = !press.moved;
  press = null;
  window.notchman.buddy('drag-end');
  if (wasClick) window.notchman.buddy(buddy.classList.contains('open') ? 'close' : 'open');
});

shiba.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  window.notchman.buddy('menu');
});

document.getElementById('tldr').addEventListener('click', () => window.notchman.buddy('tldr'));
document.getElementById('read').addEventListener('click', () => window.notchman.buddy('read'));
document.getElementById('pick').addEventListener('click', () => window.notchman.buddy('pick'));

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') window.notchman.buddy('close');
});

window.notchman.onBuddy((state) => {
  buddy.classList.toggle('open', Boolean(state.open));
  buddy.classList.toggle('left', state.side === 'left');
  for (const v of ['top', 'center', 'bottom']) buddy.classList.toggle(`v-${v}`, state.valign === v);
  buddy.classList.toggle('busy', Boolean(state.busy));
  buddy.classList.toggle('speaking', Boolean(state.speaking));
});
