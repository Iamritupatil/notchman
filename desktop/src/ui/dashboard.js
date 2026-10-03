'use strict';

// The Notchman window: tabs, plan and usage, History and the Plan page.
// The Settings tab is drawn by settings.js.

(() => {
  const $ = (id) => document.getElementById(id);
  const PLAN_NAMES = { free: 'Free', pro: 'Pro', proplus: 'Pro+' };

  function show(tab) {
    for (const button of document.querySelectorAll('.tab')) button.classList.toggle('active', button.dataset.tab === tab);
    for (const panel of document.querySelectorAll('.panel')) panel.classList.toggle('active', panel.dataset.panel === tab);
    if (tab === 'home' || tab === 'plan') loadUsage();
    if (tab === 'home' || tab === 'history') loadHistory();
  }

  for (const button of document.querySelectorAll('.tab')) button.addEventListener('click', () => show(button.dataset.tab));
  for (const link of document.querySelectorAll('[data-goto]')) link.addEventListener('click', () => show(link.dataset.goto));

  // --- Plan and usage ---------------------------------------------------------

  const percent = (used, limit) => (limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0);

  async function loadUsage() {
    const usage = await window.notchman.usage();
    if (!usage.ok) {
      $('tldrNote').textContent = usage.message || "Couldn't load your plan. Check your connection.";
      return;
    }
    const plan = PLAN_NAMES[usage.plan] || 'Free';
    $('planChip').textContent = plan;
    const period = usage.period === 'day' ? 'today' : 'this month';
    $('tldrCount').textContent = usage.limit ? `${usage.used} / ${usage.limit}` : `${usage.used}`;
    $('tldrMeter').style.width = `${percent(usage.used, usage.limit)}%`;
    $('tldrNote').textContent = usage.limit
      ? `${usage.remaining} left ${period}.${usage.plan === 'free' ? ' Upgrade for more.' : ''}`
      : 'Upgrade to Pro for TL;DRs in the Notchman voice.';
    const voicePeriod = usage.voicePeriod === 'day' ? 'today' : usage.voicePeriod === 'trial' ? 'in your free preview' : 'this month';
    const minutes = (chars) => Math.max(0, Math.round(chars / 900));
    const chars = (n) => Number(n || 0).toLocaleString();
    $('voiceCount').textContent = usage.voiceLimit ? `${chars(Math.max(0, usage.voiceLimit - usage.voiceUsed))}` : '–';
    $('voiceMeter').style.width = `${percent(usage.voiceUsed, usage.voiceLimit)}%`;
    $('voiceNote').textContent = usage.voiceLimit
      ? `characters left ${voicePeriod} of ${chars(usage.voiceLimit)} (about ${minutes(usage.voiceLimit - usage.voiceUsed)} min). After that, the free voice on your computer.`
      : 'You hear the free voice on your computer. Pro adds the Notchman voice.';
    $('planLead').textContent = usage.plan === 'free'
      ? "You're on Free: TL;DRs and reading work with the free voice on your computer. Upgrade for the Notchman voice."
      : `You're on ${plan}. Thanks for supporting Notchman!`;
    for (const card of document.querySelectorAll('.plan')) {
      const current = card.dataset.plan === usage.plan;
      card.classList.toggle('current', current);
      card.querySelector('button').textContent = current ? 'Your plan' : `Upgrade to ${PLAN_NAMES[card.dataset.plan]}`;
    }
  }

  for (const button of document.querySelectorAll('[data-upgrade]')) {
    button.addEventListener('click', () => window.notchman.upgrade(button.dataset.upgrade));
  }
  $('refreshPlan').addEventListener('click', async () => {
    $('refreshPlan').textContent = 'Checking…';
    await loadUsage();
    $('refreshPlan').textContent = "I've paid: refresh";
  });

  // --- History ----------------------------------------------------------------

  function when(at) {
    const minutes = Math.round((Date.now() - at) / 60000);
    if (minutes < 1) return 'just now';
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours} h ago`;
    return new Date(at).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  }

  function row(item) {
    const li = document.createElement('li');
    const play = Object.assign(document.createElement('button'), { className: 'play', textContent: '▶', title: 'Play again' });
    play.addEventListener('click', () => window.notchman.replay(item.id));
    const what = Object.assign(document.createElement('div'), { className: 'what' });
    what.append(
      Object.assign(document.createElement('div'), { className: 'title', textContent: item.title || item.spoken.slice(0, 80) }),
      Object.assign(document.createElement('div'), { className: 'meta', textContent: `${item.source} · ${when(item.at)}` }),
    );
    const mode = Object.assign(document.createElement('span'), { className: 'mode', textContent: item.action === 'tldr' ? 'TL;DR' : 'Read' });
    const remove = Object.assign(document.createElement('button'), { className: 'remove', textContent: '×', title: 'Remove' });
    remove.addEventListener('click', async () => render(await window.notchman.removeHistory(item.id)));
    li.append(play, what, mode, remove);
    return li;
  }

  function render(items) {
    const empty = () => Object.assign(document.createElement('li'), { className: 'empty', textContent: 'Nothing yet. Copy something and press the shortcut.' });
    $('history').replaceChildren(...(items.length ? items.map(row) : [empty()]));
    $('recent').replaceChildren(...(items.length ? items.slice(0, 4).map(row) : [empty()]));
  }

  async function loadHistory() {
    render(await window.notchman.history());
  }

  $('clearHistory').addEventListener('click', async () => {
    if (confirm('Clear your listening history on this computer?')) render(await window.notchman.clearHistory());
  });

  // --- Start ------------------------------------------------------------------

  window.notchman.onDashboard(({ tab, changed }) => {
    if (tab) show(tab);
    if (changed) { loadHistory(); loadUsage(); }
  });
  window.notchman.getSettings().then((s) => {
    const pretty = (key) => key.replace('CommandOrControl', s.platform === 'darwin' ? '⌘' : 'Ctrl').replace(/\+/g, s.platform === 'darwin' ? '' : '+');
    $('homeTldrKey').textContent = pretty(s.settings.tldrShortcut);
    $('homeReadKey').textContent = pretty(s.settings.readShortcut);
    $('installId').textContent = s.settings.installId || '';
  });
  show(new URLSearchParams(location.search).get('tab') || 'home');
})();
