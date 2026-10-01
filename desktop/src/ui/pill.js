'use strict';

// The pill at the top of the screen: shows each step, then plays the voice
// piece by piece (the first piece is short, so speech starts almost at once,
// while later pieces are voiced ahead).

const $ = (id) => document.getElementById(id);
const pillEl = $('pill');

let player = null;
let hideTimer = null;
let hovering = false;

pillEl.addEventListener('mouseenter', () => { hovering = true; });
pillEl.addEventListener('mouseleave', () => {
  hovering = false;
  if (player?.done) scheduleHide(2500);
});

window.notchman.onState((state) => {
  switch (state.kind) {
    case 'working':
      stopPlayer();
      show('working');
      $('title').textContent = state.title || (state.action === 'tldr' ? 'TL;DR' : 'Read');
      $('status').textContent = state.status;
      setControls({ stop: true });
      break;
    case 'play':
      show('speaking');
      $('title').textContent = state.title || 'Notchman';
      $('status').textContent = `${state.source} · ${state.action === 'tldr' ? 'TL;DR' : 'Reading'}`;
      setControls({ playPause: true, replay: true, original: state.canReadOriginal, stop: true });
      startPlayer(state);
      break;
    case 'error':
      stopPlayer();
      show('error');
      $('title').textContent = 'Notchman';
      $('status').textContent = state.message;
      setControls({ stop: true });
      scheduleHide(6000);
      break;
    case 'message':
      stopPlayer();
      show('message');
      $('title').textContent = state.message;
      setControls({ stop: true });
      scheduleHide(state.hideAfter || 5000);
      break;
    case 'speed':
      if (player) player.setSpeed(state.speed);
      break;
    default:
      break;
  }
});

function show(mode) {
  clearTimeout(hideTimer);
  pillEl.className = `pill ${mode}`;
  $('bar').style.width = '0%';
}

function hide() {
  clearTimeout(hideTimer);
  pillEl.classList.add('hidden');
  setTimeout(() => window.notchman.control('hide'), 220);
}

function scheduleHide(ms) {
  clearTimeout(hideTimer);
  hideTimer = setTimeout(() => {
    if (hovering) return scheduleHide(1500);
    hide();
  }, ms);
}

function setControls(visible) {
  for (const id of ['playPause', 'replay', 'original', 'stop']) {
    $(id).classList.toggle('gone', !visible[id]);
  }
}

// --- Player ------------------------------------------------------------------

function startPlayer(state) {
  stopPlayer();
  player = createPlayer(state);
  player.play(0);
}

function stopPlayer() {
  if (player) player.destroy();
  player = null;
}

function createPlayer({ id, pieceCount, speed }) {
  const audio = new Audio();
  const urls = new Map(); // index → object URL (or a pending promise)
  let index = 0;
  let destroyed = false;
  let rate = speed || 1;
  const p = { done: false };

  function load(i) {
    if (i >= pieceCount) return Promise.resolve(null);
    if (!urls.has(i)) {
      urls.set(i, window.notchman.piece(id, i).then((bytes) => {
        if (!bytes) return null;
        return URL.createObjectURL(new Blob([bytes], { type: 'audio/mpeg' }));
      }));
    }
    return urls.get(i);
  }

  async function play(i) {
    index = i;
    p.done = false;
    setPaused(false);
    const url = await load(i);
    // Voice the next two pieces while this one plays.
    load(i + 1);
    load(i + 2);
    if (destroyed || index !== i) return;
    if (!url) return; // the error is shown by the main process
    audio.src = url;
    audio.playbackRate = rate;
    audio.preservesPitch = true;
    try {
      await audio.play();
    } catch { /* interrupted by a newer action */ }
  }

  audio.addEventListener('ended', () => {
    if (index + 1 < pieceCount) {
      play(index + 1);
    } else {
      p.done = true;
      pillEl.classList.remove('speaking');
      $('bar').style.width = '100%';
      $('status').textContent = 'Done';
      setPaused(true);
      scheduleHide(4000);
    }
  });

  audio.addEventListener('timeupdate', () => {
    const part = audio.duration ? audio.currentTime / audio.duration : 0;
    $('bar').style.width = `${Math.min(100, ((index + part) / pieceCount) * 100)}%`;
  });

  function setPaused(paused) {
    $('iconPause').classList.toggle('gone', paused);
    $('iconPlay').classList.toggle('gone', !paused);
    pillEl.classList.toggle('speaking', !paused);
  }

  p.play = play;
  p.toggle = () => {
    if (p.done) return play(0);
    if (audio.paused) {
      audio.play().catch(() => {});
      setPaused(false);
      clearTimeout(hideTimer);
    } else {
      audio.pause();
      setPaused(true);
    }
  };
  p.replay = () => play(0);
  p.setSpeed = (s) => {
    rate = s;
    audio.playbackRate = s;
  };
  p.destroy = () => {
    destroyed = true;
    audio.pause();
    audio.removeAttribute('src');
    for (const pending of urls.values()) pending.then((url) => url && URL.revokeObjectURL(url));
  };
  return p;
}

// --- Buttons -------------------------------------------------------------------

$('playPause').addEventListener('click', () => player?.toggle());
$('replay').addEventListener('click', () => {
  clearTimeout(hideTimer);
  player?.replay();
});
$('original').addEventListener('click', () => window.notchman.control('original'));
$('stop').addEventListener('click', () => {
  stopPlayer();
  hide();
  window.notchman.control('stop');
});
