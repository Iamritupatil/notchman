// Scroll effects (word reveal, appear-on-view, the step list following the
// phones) and the phone menu. The page works without JS.
(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

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

  // Elements that rise in when they enter the viewport.
  const views = document.querySelectorAll('.appear-view');
  if (reduced || !('IntersectionObserver' in window)) {
    views.forEach((el) => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    }, { threshold: 0.2 });
    views.forEach((el) => io.observe(el));
  }

  // Intro text lights up word by word as you scroll.
  const text = document.querySelector('[data-reveal]');
  if (text && !reduced) {
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
    wrap(text);
    const words = [...text.querySelectorAll('.w')];
    let litMax = 0;
    const update = () => {
      const r = text.getBoundingClientRect();
      const start = innerHeight, end = innerHeight * 0.4;
      const progress = Math.min(1, Math.max(0, (start - r.top) / (start - end + r.height * 0.5)));
      // Once lit, words stay lit (like the original).
      litMax = Math.max(litMax, Math.round(progress * words.length));
      const lit = litMax;
      words.forEach((w, i) => w.classList.toggle('on', i < lit));
    };
    addEventListener('scroll', update, { passive: true });
    addEventListener('resize', update);
    update();
  }

  // The step list follows whichever phone is in the middle of the screen.
  const steps = [...document.querySelectorAll('.showcase-steps li')];
  const phones = [...document.querySelectorAll('.showcase-phones .device[data-step]')];
  if (steps.length && phones.length && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const i = Number(e.target.dataset.step);
        steps.forEach((s, j) => s.classList.toggle('is-active', i === j));
      }
    }, { rootMargin: '-45% 0px -45% 0px' });
    phones.forEach((p) => io.observe(p));
  }
})();
