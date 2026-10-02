// Scroll effects: words of the intro light up as you scroll, and the step
// list follows whichever phone is in view. Everything works without JS too.
(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const text = document.querySelector('[data-reveal]');
  if (text && !reduced) {
    // Wrap each word (keeping <em> and <br>) so it can fade in.
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
    const update = () => {
      const r = text.getBoundingClientRect();
      const start = innerHeight * 0.9, end = innerHeight * 0.35;
      const progress = Math.min(1, Math.max(0, (start - r.top) / (start - end + r.height * 0.6)));
      const lit = Math.round(progress * words.length);
      words.forEach((w, i) => w.classList.toggle('on', i < lit));
    };
    addEventListener('scroll', update, { passive: true });
    addEventListener('resize', update);
    update();
  }

  const steps = [...document.querySelectorAll('.step')];
  const phones = [...document.querySelectorAll('[data-step-target]')];
  if (steps.length && phones.length && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const i = Number(e.target.dataset.stepTarget);
        steps.forEach((s, j) => s.classList.toggle('is-active', i === j));
      }
    }, { rootMargin: '-45% 0px -45% 0px' });
    phones.forEach((p) => io.observe(p));
  }
})();
