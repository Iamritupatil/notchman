// Animations, mirroring the Framer page's own effects:
//   data-fx="y:20;op:0;s:1;blur:0;dur:1.2;delay:0;on:mount|view;th:0;replay;ease:spring|tween"
//     appear: starts from these values and settles to normal when triggered
//   data-text="by:char|word|line;y:10;blur:10;dur:.8;stagger:.05;delay:0;on:mount|view"
//     text effect: each piece appears in turn
//   data-parallax="80"  moves at 80% of scroll speed (100 = normal)
//   data-drift          moves from +50px to -50px while its section scrolls past
//   data-reveal         words light up with scroll (Framer's Text Reveal Scroll)
// Everything is visible without JS, and with reduced motion nothing moves.
(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const phone = matchMedia('(max-width: 809px)').matches;

  // Phone menu
  const nav = document.getElementById('nav');
  const burger = nav && nav.querySelector('.nav-burger');
  if (burger) {
    burger.addEventListener('click', () => {
      const open = nav.classList.toggle('open');
      burger.setAttribute('aria-expanded', String(open));
    });
    nav.querySelectorAll('.nav-links a').forEach((a) => a.addEventListener('click', () => {
      nav.classList.remove('open');
      burger.setAttribute('aria-expanded', 'false');
    }));
  }

  // Always open at the hero. Phones restore the last scroll position and old
  // #section links on reload; only /download (which redirects to #download)
  // should land somewhere else.
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
  if (location.hash && location.hash !== '#download') {
    history.replaceState(null, '', location.pathname + location.search);
  }
  if (!location.hash) scrollTo(0, 0);

  // In-page links scroll to their section without writing #section into the
  // address bar, and stop just below the fixed nav.
  let lenis = null;
  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[href*="#"]');
    if (!a) return;
    const url = new URL(a.href);
    if (url.host !== location.host || url.pathname !== location.pathname) return;
    const target = document.getElementById(url.hash.slice(1));
    if (!target) return;
    e.preventDefault();
    if (lenis) lenis.scrollTo(target, { offset: -90 });
    else target.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth' });
  });
  if (reduced) return;

  // Smooth scrolling, as on the Framer page (its Lenis component). Mouse wheel
  // and trackpad glide; touch scrolling stays native.
  if (window.Lenis) {
    lenis = new Lenis({ lerp: 0.09, wheelMultiplier: 1, autoRaf: true });
    window.notchmanScroll = lenis;
  }

  // Framer's springs (low bounce) and tweens, as CSS easings.
  const EASE = { spring: 'cubic-bezier(.2, 1.02, .3, 1)', tween: 'cubic-bezier(.12, .23, .5, 1)' };

  const parse = (spec) => {
    const o = { y: 0, op: 0, s: 1, blur: 0, dur: 1.2, delay: 0, on: 'mount', th: 0, replay: false, ease: 'spring', by: 'word', stagger: .05 };
    for (const part of spec.split(';')) {
      const [k, v] = part.split(':').map((x) => x && x.trim());
      if (!k) continue;
      if (k === 'replay') o.replay = true;
      else if (['on', 'ease', 'by'].includes(k)) o[k] = v;
      else o[k] = parseFloat(v);
    }
    return o;
  };

  const hidden = (el, o) => {
    el.style.opacity = String(o.op);
    el.style.transform = `translateY(${o.y}px) scale(${o.s})`;
    if (o.blur) el.style.filter = `blur(${o.blur}px)`;
  };
  const shown = (el) => {
    el.style.opacity = '';
    el.style.transform = '';
    el.style.filter = '';
  };
  const animate = (el, o, extraDelay = 0) => {
    const e = EASE[o.ease] || EASE.spring;
    el.style.transition = `opacity ${o.dur}s ${e}, transform ${o.dur}s ${e}, filter ${o.dur}s ${e}`;
    el.style.transitionDelay = `${o.delay + extraDelay}s`;
  };

  // Triggers: on load, or when scrolled into view (optionally every time).
  const whenVisible = (el, o, show, hide) => {
    if (o.on !== 'view') {
      requestAnimationFrame(() => requestAnimationFrame(show));
      return;
    }
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting) { show(); if (!o.replay) io.unobserve(el); }
        else if (o.replay && hide) hide();
      }
    }, { threshold: o.th || 0 });
    io.observe(el);
  };

  // Appear effects
  const appear = (el, spec) => {
    const o = parse(spec);
    hidden(el, o);
    el.getBoundingClientRect();
    animate(el, o);
    whenVisible(el, o, () => shown(el), () => { el.style.transitionDelay = '0s'; hidden(el, o); });
  };
  document.querySelectorAll('[data-fx]').forEach((el) => appear(el, el.dataset.fx));
  if (phone) document.querySelectorAll('[data-fx-mobile]').forEach((el) => appear(el, el.dataset.fxMobile));

  // Text effects: split into characters, words or lines.
  const split = (el, by) => {
    const pieces = [];
    const text = el.textContent;
    el.textContent = '';
    if (by === 'line') {
      const span = document.createElement('span');
      span.textContent = text;
      span.style.display = 'inline-block';
      el.append(span);
      return [span];
    }
    for (const word of text.split(/(\s+)/)) {
      if (!word) continue;
      if (/^\s+$/.test(word)) { el.append(word); continue; }
      const w = document.createElement('span');
      w.style.display = 'inline-block';
      w.style.whiteSpace = 'nowrap';
      if (by === 'char') {
        for (const ch of word) {
          const c = document.createElement('span');
          c.textContent = ch;
          c.style.display = 'inline-block';
          w.append(c);
          pieces.push(c);
        }
      } else {
        w.textContent = word;
        pieces.push(w);
      }
      el.append(w);
    }
    return pieces;
  };
  document.querySelectorAll('[data-text]').forEach((el) => {
    const o = parse(el.dataset.text);
    o.op = 0;
    el.setAttribute('aria-label', el.textContent);
    const pieces = split(el, o.by);
    pieces.forEach((p, i) => { p.setAttribute('aria-hidden', 'true'); hidden(p, o); animate(p, o, i * o.stagger); });
    el.getBoundingClientRect();
    whenVisible(el, o, () => pieces.forEach(shown));
  });

  // Intro words light up with scroll: from the text's top at the bottom of the
  // screen (100%) to 40% up, other words dimmed to 5%.
  const reveal = document.querySelector('[data-reveal]');
  let words = [];
  if (reveal) {
    const wrap = (node) => {
      for (const child of [...node.childNodes]) {
        if (child.nodeType === Node.TEXT_NODE) {
          const frag = document.createDocumentFragment();
          for (const part of child.textContent.split(/(\s+)/)) {
            if (!part) continue;
            if (/^\s+$/.test(part)) { frag.append(part); continue; }
            const span = document.createElement('span');
            span.className = 'w';
            span.textContent = part;
            frag.append(span);
          }
          child.replaceWith(frag);
        } else if (child.nodeType === Node.ELEMENT_NODE && child.tagName !== 'BR') {
          wrap(child);
        }
      }
    };
    wrap(reveal);
    words = [...reveal.querySelectorAll('.w')];
  }

  // Scroll-linked effects
  const parallax = [...document.querySelectorAll('[data-parallax]')];
  const drift = [...document.querySelectorAll('[data-drift]')];
  const driftSection = drift.length ? drift[0].closest('section') : null;
  let ticking = false;
  const onScroll = () => {
    ticking = false;
    const y = scrollY, vh = innerHeight;
    for (const el of parallax) {
      const speed = parseFloat(el.dataset.parallax) / 100;
      el.style.translate = `0 ${(y * (1 - speed)).toFixed(1)}px`;
    }
    if (driftSection) {
      // 0 when the section's top reaches the bottom of the screen, 1 when its end does.
      const r = driftSection.getBoundingClientRect();
      const t = Math.min(1, Math.max(0, (vh - r.top) / (r.height || 1)));
      const off = 50 - 100 * t;
      for (const el of drift) el.style.translate = `0 ${off.toFixed(1)}px`;
    }
    if (words.length) {
      const r = reveal.getBoundingClientRect();
      const start = vh, end = vh * 0.5;
      const progress = Math.min(1, Math.max(0, (start - r.top) / (start - end)));
      const lit = Math.round(progress * words.length);
      words.forEach((w, i) => w.classList.toggle('on', i < lit));
    }
  };
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
  addEventListener('resize', onScroll);
  onScroll();

  // The step list switches as each phone reaches the middle of the screen.
  const steps = [...document.querySelectorAll('.showcase-steps li')];
  const phones = [...document.querySelectorAll('.showcase-phones .device[data-step]')];
  if (steps.length && phones.length && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const i = Number(e.target.dataset.step);
        steps.forEach((s, j) => s.classList.toggle('is-active', i === j));
      }
    }, { rootMargin: '-50% 0px -50% 0px' });
    phones.forEach((p) => io.observe(p));
  }
})();
