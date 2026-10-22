'use strict';

// Anonymous usage counts for the owner's dashboard: event names only (like
// "tldr_selected" or "audio_completed"), never the text, links or anything
// typed. Sent in small batches with the install ID, which the server turns
// into daily counts (server/src/site-analytics.ts). The Community edition
// sends nothing.

const EVENTS = new Set([
  'first_launch', 'second_session', 'content_submitted', 'read_selected', 'tldr_selected', 'audio_started',
  'audio_completed', 'paywall_viewed', 'pro_button_tap', 'pro_selected', 'pro_selected_pro', 'pro_selected_proplus',
  'checkout_opened', 'checkout_failed', 'summary_failed', 'too_long', 'nothing_copied', 'pick_selected',
]);

const day = (date = new Date()) => date.toISOString().slice(0, 10);

function createAnalytics({ send, settings, enabled = true, flushMs = 20_000 }) {
  let queue = [];
  let timer = null;

  function flush() {
    clearTimeout(timer);
    timer = null;
    if (!queue.length) return Promise.resolve();
    const events = queue.splice(0, 40);
    return send(events).catch(() => {
      // Offline: keep them for the next try (a few at most).
      queue = events.concat(queue).slice(0, 200);
    });
  }

  function track(name) {
    // Settings › Share anonymous usage statistics turns this off.
    if (!enabled || settings.get('shareStats') === false || !EVENTS.has(name)) return;
    queue.push(name);
    if (!timer) timer = setTimeout(flush, flushMs);
  }

  /** At start: the first launch of this install, once. */
  function launched() {
    if (!settings.get('firstLaunchAt')) {
      settings.set({ firstLaunchAt: new Date().toISOString() });
      track('first_launch');
    }
  }

  /**
   * Each time something is listened to: a use on a later day than the first
   * use is the second session (counted once).
   */
  function used() {
    const today = day();
    const first = settings.get('firstUseDay');
    if (!first) settings.set({ firstUseDay: today });
    else if (first !== today && !settings.get('secondSessionSent')) {
      settings.set({ secondSessionSent: true });
      track('second_session');
    }
  }

  /** After the first complete listen, Upgrade may be offered. */
  function listened() {
    if (!settings.get('listenedOnce')) settings.set({ listenedOnce: true });
  }

  return { track, flush, launched, used, listened, hasListened: () => Boolean(settings.get('listenedOnce')) };
}

module.exports = { createAnalytics, EVENTS };
