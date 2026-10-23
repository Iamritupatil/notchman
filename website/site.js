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

  // Analytics without cookies (server/src/site-analytics.ts): the server keeps
  // daily counts only. Browsers that ask not to be tracked aren't.
  const EVENTS = 'https://x6clb2pbdxbr55i5sdradcnqw40bmqrt.lambda-url.us-east-1.on.aws/event';
  // The owner's own browsers: open notchman.app/?me=1 once to never be counted.
  const owner = (() => {
    try {
      if (new URLSearchParams(location.search).get('me') === '1') localStorage.setItem('notchman-me', '1');
      return localStorage.getItem('notchman-me') === '1';
    } catch { return false; }
  })();
  const optedOut = navigator.globalPrivacyControl === true || navigator.doNotTrack === '1' || owner
    || document.documentElement.classList.contains('in-app');
  const track = (data) => {
    if (optedOut) return;
    const body = JSON.stringify({ p: location.pathname, ...data });
    try {
      if (navigator.sendBeacon && navigator.sendBeacon(EVENTS, body)) return;
    } catch { /* fall back to fetch */ }
    fetch(EVENTS, { method: 'POST', body, keepalive: true, mode: 'no-cors' }).catch(() => {});
  };
  // Where this visit came from; also sent with key clicks (Pro, downloads) so
  // the report can say which source they came from.
  // Links carry ?source=instagram (or tiktok, x, direct…); kept for this visit
  // so it still counts after moving to another page.
  const tagged = (() => {
    const params = new URLSearchParams(location.search);
    const value = (params.get('source') || params.get('utm_source') || '').trim().toLowerCase().slice(0, 40);
    try {
      if (value) sessionStorage.setItem('notchman-source', value);
      return value || sessionStorage.getItem('notchman-source') || undefined;
    } catch { return value || undefined; }
  })();
  const source = { r: document.referrer, u: tagged };
  track({ e: 'view', ...source });
  // Phones can't install the Mac or Windows app, and Instagram's and Facebook's
  // built-in browsers don't download files at all: a tap on a desktop download
  // there opens a note that sends the link to their computer instead.
  const onPhone = /iPhone|iPod|Android.*Mobile|Mobi/i.test(navigator.userAgent);
  const phoneNote = document.getElementById('phone-download');
  const macHelp = document.getElementById('mac-open');
  if (macHelp) macHelp.addEventListener('click', (event) => { if (event.target === macHelp) macHelp.close(); });

  // Desktop downloads ask for an email first (server/src/signups.ts). It's
  // remembered in this browser, so the next download (say, for Intel Macs)
  // starts at once; each download still tells the server, so the app can be
  // linked to it when it first opens.
  const SIGNUP = EVENTS.replace(/\/event$/, '/signup');
  const emailSheet = document.getElementById('email-download');
  const EMAIL = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;
  const savedEmail = () => { try { return localStorage.getItem('notchman-email') || ''; } catch { return ''; } };
  const platformOf = (link) => ({ download_windows: 'windows', download_mac: 'mac', download_mac_intel: 'mac-intel' })[link.dataset.track];
  const sourceName = () => {
    if (source.u) return source.u;
    try { return source.r ? new URL(source.r).hostname : 'direct'; } catch { return 'direct'; }
  };
  const signup = (email, platform) => {
    const body = JSON.stringify({ email, platform, source: sourceName() });
    try {
      if (navigator.sendBeacon && navigator.sendBeacon(SIGNUP, body)) return;
    } catch { /* fall back to fetch */ }
    fetch(SIGNUP, { method: 'POST', body, keepalive: true, mode: 'no-cors' }).catch(() => {});
  };
  const startDownload = (link) => {
    // The download counter hears where this person came from.
    const from = sourceName();
    location.href = from === 'direct' ? link.getAttribute('href') : `${link.getAttribute('href')}?s=${encodeURIComponent(from)}`;
    if (macHelp && macHelp.showModal && /^mac/.test(platformOf(link) || '')) setTimeout(() => macHelp.showModal(), 600);
  };
  let pendingLink = null;
  if (emailSheet) {
    const form = emailSheet.querySelector('[data-email-form]');
    const input = form.querySelector('input');
    const error = form.querySelector('[data-email-error]');
    input.addEventListener('input', () => { error.hidden = true; });
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const email = input.value.trim();
      if (!EMAIL.test(email)) { error.hidden = false; input.focus(); return; }
      try { localStorage.setItem('notchman-email', email); } catch { /* private window */ }
      const link = pendingLink;
      emailSheet.close();
      if (!link) return;
      signup(email, platformOf(link));
      track({ e: 'click', t: 'email_given', ...source });
      startDownload(link);
    });
    emailSheet.addEventListener('click', (event) => { if (event.target === emailSheet) emailSheet.close(); });
  }
  document.addEventListener('click', (event) => {
    const target = event.target.closest && event.target.closest('[data-track]');
    if (!target) return;
    const phoneTap = onPhone && phoneNote && phoneNote.showModal && target.matches('a[data-track^="download_"]');
    track({ e: 'click', t: phoneTap ? `phone_${target.dataset.track}` : target.dataset.track, ...source });
    if (!phoneTap) {
      if (target.matches('[data-mac-help]') && macHelp && macHelp.showModal) { macHelp.showModal(); return; }
      if (!platformOf(target) || !target.matches('a[href^="/download/"]')) return;
      event.preventDefault();
      const email = savedEmail();
      if (email || !emailSheet || !emailSheet.showModal) {
        if (email) signup(email, platformOf(target));
        startDownload(target);
        return;
      }
      // First download: the email, then the download.
      pendingLink = target;
      emailSheet.querySelector('[data-dl-platform]').textContent = target.dataset.track === 'download_windows' ? 'Windows' : 'Mac';
      emailSheet.showModal();
      emailSheet.querySelector('input').focus();
      return;
    }
    event.preventDefault();
    phoneNote.querySelector('[data-phone-platform]').textContent = target.dataset.track === 'download_windows' ? 'Windows' : 'Mac';
    phoneNote.querySelector('[data-phone-anyway]').href = target.getAttribute('href');
    phoneNote.showModal();
  });
  if (phoneNote) {
    phoneNote.addEventListener('click', (event) => { if (event.target === phoneNote) phoneNote.close(); });
    phoneNote.querySelector('[data-phone-send]').addEventListener('click', async (event) => {
      const button = event.currentTarget;
      const url = 'https://notchman.app/#download';
      if (navigator.share) {
        try { await navigator.share({ title: 'Notchman for Mac and Windows', url }); return; } catch (error) { if (error.name === 'AbortError') return; }
      }
      try {
        await navigator.clipboard.writeText(url);
        button.textContent = 'Link copied: open it on your computer';
      } catch {
        location.href = `mailto:?subject=${encodeURIComponent('Notchman for my computer')}&body=${encodeURIComponent(url)}`;
      }
    });
  }
  // "Join the iPhone beta": email, device and what they want to listen to.
  const betaSheet = document.getElementById('iphone-beta');
  if (betaSheet && betaSheet.showModal) {
    const form = betaSheet.querySelector('[data-beta-form]');
    const error = betaSheet.querySelector('[data-beta-error]');
    form.email.addEventListener('input', () => { error.hidden = true; });
    // On a phone (most people coming from a reel), the Download buttons can't
    // install anything: they offer the iPhone beta instead.
    const PHONE_CTAS = '[data-track="hero_download"], [data-track="nav_download"], [data-track="intro_download"], [data-track="footer_download"]';
    if (onPhone) {
      for (const cta of document.querySelectorAll(PHONE_CTAS)) {
        cta.setAttribute('data-beta', '');
        if (cta.dataset.track !== 'nav_download') cta.firstChild.textContent = 'Get it on iPhone ';
        else cta.textContent = 'iPhone beta';
      }
    }
    document.addEventListener('click', (event) => {
      if (!event.target.closest || !event.target.closest('[data-beta]')) return;
      event.preventDefault();
      const saved = savedEmail();
      if (saved && !form.email.value) form.email.value = saved;
      betaSheet.showModal();
      form.email.focus();
    });
    betaSheet.addEventListener('click', (event) => { if (event.target === betaSheet) betaSheet.close(); });
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      const email = form.email.value.trim();
      if (!EMAIL.test(email)) { error.hidden = false; form.email.focus(); return; }
      try { localStorage.setItem('notchman-email', email); } catch { /* private window */ }
      const body = JSON.stringify({ email, device: form.device.value, wants: form.wants.value.trim(), source: sourceName() });
      fetch(EVENTS.replace(/\/event$/, '/beta'), { method: 'POST', body, keepalive: true, mode: 'no-cors' }).catch(() => {});
      track({ e: 'click', t: 'beta_signup', ...source });
      betaSheet.querySelector('[data-beta-ask]').hidden = true;
      betaSheet.querySelector('[data-beta-done]').hidden = false;
    });
  }
  const depths = new Set();
  addEventListener('scroll', () => {
    const page = document.documentElement;
    const reached = ((scrollY + innerHeight) / page.scrollHeight) * 100;
    for (const depth of [25, 50, 75, 100]) {
      if (reached >= depth - 1 && !depths.has(depth)) { depths.add(depth); track({ e: 'scroll', d: depth }); }
    }
  }, { passive: true });
  document.querySelectorAll('.faq details, .guide-faq details').forEach((item) => item.addEventListener('toggle', () => {
    if (item.open) track({ e: 'faq', t: item.querySelector('summary').textContent.trim().slice(0, 40) });
  }));
  const openedAt = Date.now();
  let timeSent = false;
  const trackTime = () => {
    if (timeSent) return;
    timeSent = true;
    track({ e: 'time', d: Math.round((Date.now() - openedAt) / 1000) });
  };
  addEventListener('pagehide', trackTime);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') trackTime(); });

  // Copy buttons (the Community edition's commands)
  document.querySelectorAll('[data-copy]').forEach((button) => button.addEventListener('click', async () => {
    const source = document.getElementById(button.dataset.copy);
    try {
      await navigator.clipboard.writeText(source.textContent.trim());
      button.textContent = 'Copied';
      track({ e: 'copy', t: button.dataset.copy });
    } catch {
      button.textContent = 'Select and copy';
    }
    setTimeout(() => { button.textContent = 'Copy'; }, 2000);
  }));

  // The setup guide: Windows or Mac steps.
  document.querySelectorAll('[data-os-pick]').forEach((button) => button.addEventListener('click', () => {
    document.documentElement.dataset.os = button.dataset.osPick;
    track({ e: 'click', t: `guide_os_${button.dataset.osPick}` });
  }));

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
