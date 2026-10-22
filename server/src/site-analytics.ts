import { createHash } from "node:crypto";
import { dayKey, days, type QuotaStore } from "./quota.js";

/**
 * Website analytics without cookies or personal data: notchman.app sends
 * small events (page view, clicks on Download / GitHub / Pro, scroll depth,
 * FAQ opens, time on page) and we keep only daily counters. Unique visitors
 * are counted like Plausible: a one-way hash of the day, IP address and
 * browser, which changes every day and is never stored in readable form.
 */

const ALL = Number.MAX_SAFE_INTEGER;
const PAGES = ["/", "/privacy", "/terms", "/thanks"];
const TIME_BUCKETS: [number, string][] = [[10, "0-10s"], [30, "10-30s"], [60, "30-60s"], [180, "1-3min"], [Infinity, "3min+"]];

/** a-z, 0-9, dot, dash and underscore; at most 40 characters. */
export function label(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const clean = value.toLowerCase().normalize("NFKD").replace(/[^a-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40);
  return clean || undefined;
}

/** The site that sent the visitor ("google.com", "x.com"), never the full address. */
export function referrerDomain(value: unknown): string | undefined {
  if (typeof value !== "string" || !value) return undefined;
  try {
    const host = new URL(value).hostname.replace(/^www\./, "");
    if (!host || host.endsWith("notchman.app")) return undefined;
    return label(host);
  } catch {
    return undefined;
  }
}

/** Short names people use in links (?source=ig) → one name per place. */
const SOURCE_ALIASES: Record<string, string> = {
  ig: "instagram", insta: "instagram", instagram: "instagram", "l.instagram.com": "instagram", "instagram.com": "instagram",
  tt: "tiktok", tiktok: "tiktok", "tiktok.com": "tiktok", x: "x", twitter: "x", "t.co": "x", "x.com": "x", "twitter.com": "x",
  fb: "facebook", facebook: "facebook", "facebook.com": "facebook", "l.facebook.com": "facebook", "m.facebook.com": "facebook",
  wa: "whatsapp", whatsapp: "whatsapp", "wa.me": "whatsapp", "web.whatsapp.com": "whatsapp", li: "linkedin", linkedin: "linkedin",
  "linkedin.com": "linkedin", "lnkd.in": "linkedin", yt: "youtube", youtube: "youtube", "youtube.com": "youtube",
  reddit: "reddit", "reddit.com": "reddit", ph: "producthunt", producthunt: "producthunt", "producthunt.com": "producthunt",
  google: "google", "google.com": "google", direct: "direct",
};

/** Apps whose built-in browsers send no referrer, but say who they are. */
const IN_APP: [RegExp, string][] = [
  [/Instagram/i, "instagram"], [/FBAN|FBAV|FB_IAB/i, "facebook"], [/musical_ly|TikTok|BytedanceWebview|trill/i, "tiktok"],
  [/Twitter/i, "x"], [/WhatsApp/i, "whatsapp"], [/LinkedInApp/i, "linkedin"], [/Snapchat/i, "snapchat"],
];

/**
 * Where a visit came from, in one word: the link's ?source= (or utm_source),
 * else the app whose built-in browser opened it, else the referring site,
 * else "direct" (typed, a bookmark, or a link pasted without a source).
 */
export function sourceOf(visit: { u?: unknown; r?: unknown; userAgent?: string }): string {
  const tagged = label(visit.u);
  if (tagged) return SOURCE_ALIASES[tagged] ?? tagged;
  const app = IN_APP.find(([pattern]) => pattern.test(visit.userAgent ?? ""));
  if (app) return app[1];
  const ref = referrerDomain(visit.r);
  if (ref) return SOURCE_ALIASES[ref] ?? ref;
  return "direct";
}

export function device(userAgent: string | undefined): "phone" | "tablet" | "desktop" {
  const ua = userAgent ?? "";
  if (/iPad|Tablet/i.test(ua)) return "tablet";
  return /Mobi|iPhone|Android/i.test(ua) ? "phone" : "desktop";
}

const BOTS = /bot|crawl|spider|slurp|preview|facebookexternalhit|headless|lighthouse|pingdom|uptime/i;

/** Website clicks worth knowing the time and source of: Pro interest and downloads. */
const KEY_CLICKS = new Set(["beta_open", "beta_signup", "get_pro", "download_mac", "download_mac_intel", "download_windows", "phone_download_mac",
                            "phone_download_mac_intel", "phone_download_windows", "phone_send_link", "github"]);

/**
 * A key action with its time (to the minute, UTC), where the visit came from
 * and the kind of device: nothing that identifies anyone. Kept as a counter
 * named `t|HHMM|channel|action|source|device` for the day.
 */
async function logKeyAction(store: QuotaStore, now: Date, channel: string, action: string, source: string, kind: string) {
  const hhmm = now.toISOString().slice(11, 16).replace(":", "");
  await store.consume(`site_${dayKey(now)}_t|${hhmm}|${channel}|${action}|${source}|${kind}`, ALL, days(400, now));
}

export interface SiteEvent {
  e?: unknown; // view | click | scroll | faq | copy | time
  p?: unknown; // page path
  t?: unknown; // what was clicked / opened
  r?: unknown; // referrer (view)
  u?: unknown; // utm_source (view)
  d?: unknown; // scroll % or seconds
}

/** Counts one event. Returns the counter keys it touched (for tests). */
export async function recordSiteEvent(store: QuotaStore, event: SiteEvent, visitor: { ip?: string; userAgent?: string; pepper?: string },
                                      now = new Date()): Promise<string[]> {
  if (BOTS.test(visitor.userAgent ?? "")) return [];
  const day = dayKey(now);
  const keep = days(400, now);
  const page = typeof event.p === "string" && PAGES.includes(event.p.replace(/\/+$/, "") || "/") ? (event.p.replace(/\/+$/, "") || "/") : "/";
  const keys: string[] = [];
  const count = async (name: string) => {
    const key = `site_${day}_${name}`;
    await store.consume(key, ALL, keep);
    keys.push(key);
  };

  // A burst from one visitor (a script, a loop) can't flood the counters.
  const visitorHash = createHash("sha256")
    .update(`${day}|${visitor.pepper ?? ""}|${visitor.ip ?? ""}|${visitor.userAgent ?? ""}`).digest("hex").slice(0, 32);
  const rate = await store.consume(`siterate_${visitorHash}_${now.toISOString().slice(0, 16)}`, 60, days(1, now));
  if (!rate.allowed) return [];

  switch (event.e) {
    case "view": {
      await count(`view_${label(page) ?? "home"}`);
      const first = await store.consume(`sitevisitor_${visitorHash}`, 1, days(2, now));
      if (first.allowed) {
        await count("visitors");
        await count(`device_${device(visitor.userAgent)}`);
        const ref = referrerDomain(event.r);
        await count(`ref_${ref ?? "direct"}`);
        const utm = label(event.u);
        if (utm) await count(`utm_${utm}`);
        await count(`src_${sourceOf({ u: event.u, r: event.r, userAgent: visitor.userAgent })}`);
      }
      break;
    }
    case "click":
    case "faq": {
      const what = label(event.t);
      if (what) await count(`${event.e}_${what}`);
      if (event.e === "click" && what && KEY_CLICKS.has(what)) {
        const utm = label(event.u);
        const source = (referrerDomain(event.r) ?? "direct") + (utm ? `+${utm}` : "");
        await logKeyAction(store, now, "web", what, source, device(visitor.userAgent));
      }
      break;
    }
    case "copy":
      await count(`copy_${label(event.t) ?? "commands"}`);
      break;
    case "scroll": {
      const depth = Number(event.d);
      if ([25, 50, 75, 100].includes(depth)) await count(`scroll_${depth}`);
      break;
    }
    case "time": {
      const seconds = Number(event.d);
      if (Number.isFinite(seconds) && seconds >= 0) await count(`time_${TIME_BUCKETS.find(([max]) => seconds < max)![1]}`);
      break;
    }
    default:
      break;
  }
  return keys;
}

const CLICK_NAMES: Record<string, string> = {
  hero_download: "Hero: Download free",
  hero_community: "Hero: Run it yourself",
  nav_download: "Menu: Download",
  nav_community: "Menu: Run it free",
  download_mac: "Download for Mac",
  download_mac_intel: "Download for Intel Mac",
  download_windows: "Download for Windows",
  github: "View on GitHub",
  get_pro: "Get Notchman Pro",
  footer_download: "Footer: Download free",
  intro_download: "Intro: Download",
  github_faq: "FAQ: GitHub link",
  phone_download_mac: "Download for Mac, tapped on a phone",
  phone_download_mac_intel: "Download for Intel Mac, tapped on a phone",
  phone_download_windows: "Download for Windows, tapped on a phone",
  phone_send_link: "Phone: sent the link to their computer",
  phone_download_anyway: "Phone: downloaded anyway",
  mac_open_help: "Mac: opened the how-to-open steps",
  email_given: "Gave their email, then downloaded",
  beta_open: "Opened Join the iPhone beta",
  beta_signup: "Joined the iPhone beta",
};

/** The last `span` days of website numbers, as plain text for the owner. */
export async function siteReport(store: QuotaStore, now = new Date(), span = 7): Promise<string> {
  if (!store.scanPrefix) return "Site analytics need the DynamoDB store.";
  const dates = Array.from({ length: span }, (_, i) => dayKey(new Date(now.getTime() - i * 86_400_000)));
  const totals = new Map<string, number>();
  const perDay = new Map<string, number>();
  const byDay = new Map<string, number>();
  const perDayCount = (day: string, name: string) => byDay.get(`${day}|${name}`) ?? 0;
  for (const { key, count } of await store.scanPrefix("site_")) {
    const match = /^site_(\d{4}-\d{2}-\d{2})_(.+)$/.exec(key);
    if (!match || !dates.includes(match[1])) continue;
    totals.set(match[2], (totals.get(match[2]) ?? 0) + count);
    if (match[2] === "visitors") perDay.set(match[1], count);
    byDay.set(`${match[1]}|${match[2]}`, count);
  }
  const get = (name: string) => totals.get(name) ?? 0;
  const group = (prefix: string, names: Record<string, string> = {}, limit = 10) => [...totals]
    .filter(([name]) => name.startsWith(prefix))
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, n]) => `  ${n.toLocaleString("en-US").padStart(6)}  ${names[name.slice(prefix.length)] ?? name.slice(prefix.length).replace(/_/g, " ")}`);
  const visitors = get("visitors");
  const pageViews = [...totals].filter(([name]) => name.startsWith("view_")).reduce((sum, [, n]) => sum + n, 0);
  const pct = (n: number) => (visitors ? ` (${Math.round((n / visitors) * 100)}% of visitors)` : "");
  const downloads = get("click_download_mac") + get("click_download_mac_intel") + get("click_download_windows");
  const exactDownloads = get("dl_windows") + get("dl_mac") + get("dl_mac-intel");
  const phoneTaps = get("click_phone_download_mac") + get("click_phone_download_mac_intel") + get("click_phone_download_windows");
  // Key actions, newest first. byDay keys: "day|t|HHMM|channel|action|source|device".
  const keyActions = [...byDay].flatMap(([key, n]) => {
    const [d, marker, hhmm, channel, action, source, kind] = key.split("|");
    if (marker !== "t" || !kind) return [];
    const where = channel === "web" ? "website" : channel === "dl" ? "download" : channel === "apptf" ? "TestFlight" : "iPhone app";
    const what = CLICK_NAMES[action] ?? action.replace(/_/g, " ");
    return [{ sort: `${d}${hhmm}`, text: `  ${d} ${hhmm.slice(0, 2)}:${hhmm.slice(2)}  ${where.padEnd(10)}  ${what.padEnd(28)}  ${source}  ${kind}${n > 1 ? `  ×${n}` : ""}` }];
  }).sort((a, b) => b.sort.localeCompare(a.sort)).slice(0, 40).map((row) => row.text);
  const appLines = (channel: string) => {
    const rows = [...totals].filter(([name]) => name.startsWith(`${channel}_`))
      .sort((a, b) => b[1] - a[1]).slice(0, 30)
      .map(([name, n]) => `  ${n.toLocaleString("en-US").padStart(6)} · ${get(`${channel}u_${name.slice(channel.length + 1)}`).toLocaleString("en-US").padStart(4)}  ${name.slice(channel.length + 1).replace(/_/g, " ")}`);
    return rows.length ? rows : ["  (none yet)"];
  };
  const lines = [
    `notchman.app, last ${span} days (${dates[dates.length - 1]} to ${dates[0]}, UTC)`,
    "",
    `Visitors: ${visitors.toLocaleString("en-US")}   Page views: ${pageViews.toLocaleString("en-US")}`,
    `Downloads: ${exactDownloads} (by ${get("dlpeople_windows") + get("dlpeople_mac") + get("dlpeople_mac-intel")} people)   Download clicks: ${downloads}${pct(downloads)}${phoneTaps ? `, plus ${phoneTaps} on phones` : ""}   GitHub clicks: ${get("click_github")}${pct(get("click_github"))}`,
    `Automated link checks (scanners, not counted as downloads): ${get("dlauto")}`,
    `Emails given before downloading: ${get("signup_windows") + get("signup_mac") + get("signup_mac-intel") + get("signup_unknown")}`,
    `Desktop app: ${get("appnew_windows") + get("appnew_mac")} new installs, opened by ${get("appactive_windows") + get("appactive_mac")} (people-days)   Checkouts completed (thank-you page): ${get("view_thanks")}`,
    "",
    "Downloads per day (from the website's download links: started / people):",
    ...dates.slice().reverse().map((d) => {
      const parts = Object.keys(DOWNLOAD_FILES).map((p) => `${p} ${perDayCount(d, `dl_${p}`)}/${perDayCount(d, `dlpeople_${p}`)}`);
      return `  ${d}  ${parts.join("   ")}`;
    }),
    "",
    `Get Notchman Pro taps per day: ${dates.slice().reverse().map((d) => `${d.slice(5)} ${perDayCount(d, "click_get_pro")}`).join(", ")}`,
    "",
    "Desktop app per day (new installs / people who opened it):",
    ...dates.slice().reverse().map((d) => `  ${d}  windows ${perDayCount(d, "appnew_windows")}/${perDayCount(d, "appactive_windows")}   mac ${perDayCount(d, "appnew_mac")}/${perDayCount(d, "appactive_mac")}`),
    ...(group("appversion_").length ? ["App versions in use:", ...group("appversion_")] : []),
    "",
    "Visitors per day:",
    ...dates.slice().reverse().map((d) => `  ${d}  ${(perDay.get(d) ?? 0).toLocaleString("en-US")}`),
    "",
    "Where they came from:", ...(group("ref_").length ? group("ref_") : ["  (none yet)"]),
    ...(group("utm_").length ? ["", "Campaigns (utm_source):", ...group("utm_")] : []),
    "",
    "Devices:", ...(group("device_").length ? group("device_") : ["  (none yet)"]),
    "",
    "Pages:", ...(group("view_").length ? group("view_") : ["  (none yet)"]),
    "",
    "Clicks:", ...(group("click_", CLICK_NAMES, 20).length ? group("click_", CLICK_NAMES, 20) : ["  (none yet)"]),
    "",
    "Community setup commands copied (home page and /community guide, by step):",
    ...(group("copy_", {}, 15).length ? group("copy_", {}, 15) : ["  (none yet)"]),
    "",
    "How far down they scrolled:",
    ...[25, 50, 75, 100].map((d) => `  ${get(`scroll_${d}`).toLocaleString("en-US").padStart(6)}  reached ${d}%`),
    "",
    "Time on the page:", ...(group("time_").length ? group("time_") : ["  (none yet)"]),
    "",
    "FAQ questions opened:", ...(group("faq_", {}, 15).length ? group("faq_", {}, 15) : ["  (none yet)"]),
    "",
    "Key actions (time UTC · where · what · came from · device):", ...(keyActions.length ? keyActions : ["  (none yet)"]),
    "",
    "iPhone app (times · people-days):", ...appLines("app"),
    "",
    "iPhone app on TestFlight (your testing; times · people-days):", ...appLines("apptf"),
    "",
    "No cookies and no personal data: only daily counts, and for key actions the minute, source and device. Downloads are counted when the website's download links are used; app numbers come from the apps.",
  ];
  return lines.join("\n");
}

// --- Downloads and desktop app use --------------------------------------------

export const DOWNLOAD_FILES: Record<string, string> = {
  windows: "Notchman-Setup.exe",
  mac: "Notchman.dmg",
  "mac-intel": "Notchman-Intel.dmg",
};

/** Counts one download started from notchman.app (and once per person per day). */
export async function recordDownload(store: QuotaStore, platform: string,
                                     visitor: { ip?: string; userAgent?: string; pepper?: string; automated?: boolean; referer?: string; source?: string },
                                     now = new Date()): Promise<void> {
  if (!(platform in DOWNLOAD_FILES)) return;
  const day = dayKey(now);
  const keep = days(400, now);
  const kind = device(visitor.userAgent);
  // Link checkers and scanners: counted apart, never as downloads.
  if (visitor.automated || BOTS.test(visitor.userAgent ?? "")) {
    await store.consume(`site_${day}_dlauto`, ALL, keep);
    await logKeyAction(store, now, "dl", platform, "automated", kind);
    return;
  }
  const from = /notchman\.app/.test(visitor.referer ?? "") ? "website" : referrerDomain(visitor.referer) ?? "direct";
  await logKeyAction(store, now, "dl", platform, from, kind);
  await store.consume(`site_${day}_dl_${platform}`, ALL, keep);
  const person = createHash("sha256").update(`${day}|${visitor.pepper ?? ""}|${visitor.ip ?? ""}|${visitor.userAgent ?? ""}`).digest("hex").slice(0, 32);
  const first = await store.consume(`sitedl_${person}_${platform}`, 1, days(2, now));
  if (first.allowed) {
    await store.consume(`site_${day}_dlpeople_${platform}`, ALL, keep);
    // Where the person who downloaded first came from (the website passes it on).
    const source = label(visitor.source) ? sourceOf({ u: visitor.source })
      : sourceOf({ r: from === "website" ? undefined : visitor.referer, userAgent: visitor.userAgent });
    await store.consume(`site_${day}_dlsrc_${source}`, ALL, keep);
  }
}

/**
 * The desktop app says hello when it starts and once a day: counts new
 * installs and daily active installs per platform and version. Only a hash
 * of the install ID is kept, to tell "new" from "seen before".
 */
export async function recordAppHello(store: QuotaStore, installId: string, body: { platform?: unknown; version?: unknown; edition?: unknown },
                                     now = new Date()): Promise<{ new: boolean; firstToday: boolean }> {
  const platform = ({ win32: "windows", darwin: "mac", linux: "linux", ios: "iphone" } as Record<string, string>)[String(body.platform)] ?? "other";
  const version = typeof body.version === "string" && /^\d+\.\d+\.\d+$/.test(body.version) ? body.version : "unknown";
  const day = dayKey(now);
  const keep = days(400, now);
  const install = createHash("sha256").update(`notchman-install:${installId}`).digest("hex").slice(0, 32);
  const seen = await store.consume(`appseen_${install}`, 1, days(400, now));
  if (seen.allowed) await store.consume(`site_${day}_appnew_${platform}`, ALL, keep);
  const today = await store.consume(`appday_${install}_${day}`, 1, days(2, now));
  if (today.allowed) {
    await store.consume(`site_${day}_appactive_${platform}`, ALL, keep);
    await store.consume(`site_${day}_appversion_${label(version) ?? "unknown"}`, ALL, keep);
  }
  return { new: seen.allowed, firstToday: today.allowed };
}

/** iPhone app events: a short name (anything else is ignored). */
const APP_EVENT = /^[a-z][a-z0-9_]{1,39}$/;
/** The purchase funnel: kept with its time, like the website's key clicks. */
const APP_KEY_EVENT = /^(paywall_open|subscribe_tap_[a-z]+|purchase_[a-z_]+|restore_[a-z]+|limit_[a-z]+)$/;
/** The desktop app's funnel steps, kept with their time. */
const DESK_KEY_EVENT = /^(first_launch|second_session|paywall_viewed|pro_button_tap|pro_selected_[a-z]+|checkout_[a-z]+|too_long)$/;
const DESK_PLATFORMS: Record<string, string> = { win32: "windows", darwin: "mac", linux: "linux" };

/** A server-side funnel step (checkout started, payment completed, first paid session): a daily count. */
export async function countFunnel(store: QuotaStore, name: string, now = new Date()): Promise<void> {
  await store.consume(`site_${dayKey(now)}_${name}`, ALL, days(400, now));
}

/**
 * Anonymous usage statistics from the iPhone app (Privacy Policy, "App usage
 * statistics"): which features are used, never what anyone reads. Daily
 * totals, plus how many people did each thing that day, counted with a
 * one-way code made from the day and the install ID (it changes every day).
 * TestFlight builds are counted apart, so testing doesn't mix with real use.
 */
export async function recordAppEvents(store: QuotaStore, installId: string, body: { events?: unknown; testflight?: unknown; platform?: unknown },
                                      now = new Date()): Promise<number> {
  const events = Array.isArray(body.events) ? body.events.slice(0, 40) : [];
  // The Windows and Mac apps say their platform; the iPhone app doesn't.
  const desktop = DESK_PLATFORMS[String(body.platform)];
  const channel = desktop ? "desk" : body.testflight === true ? "apptf" : "app";
  const day = dayKey(now);
  const keep = days(400, now);
  const person = createHash("sha256").update(`notchman-stats:${day}:${installId}`).digest("hex").slice(0, 32);
  const rate = await store.consume(`apprate_${person}_${now.toISOString().slice(0, 13)}`, 400, days(1, now), Math.max(events.length, 1));
  if (!rate.allowed) return 0;
  let counted = 0;
  for (const raw of events) {
    const name = typeof raw === "string" ? raw : (raw as { e?: unknown } | null)?.e;
    if (typeof name !== "string" || !APP_EVENT.test(name)) continue;
    await store.consume(`site_${day}_${channel}_${name}`, ALL, keep);
    const first = await store.consume(`appevseen_${person}_${channel}_${name}`, 1, days(2, now));
    if (first.allowed) await store.consume(`site_${day}_${channel}u_${name}`, ALL, keep);
    if (desktop ? DESK_KEY_EVENT.test(name) : APP_KEY_EVENT.test(name)) await logKeyAction(store, now, channel, name, "app", desktop ?? "iphone");
    counted++;
  }
  return counted;
}

// --- Dashboard ----------------------------------------------------------------

/** Counters the dashboard draws per day; everything else is only totalled. */
const DAILY = /^(visitors|dlauto|click_get_pro|click_github|view_thanks|dl_.+|dlpeople_.+|appnew_.+|appactive_.+|signup_.+|app_hello|app_.+|desku?_.+|beta_signup|checkout_started|payment_completed|first_paid_session)$/;

export interface SiteStats {
  days: string[];
  totals: Record<string, number>;
  daily: Record<string, Record<string, number>>;
  keyActions: { day: string; time: string; channel: string; action: string; source: string; device: string; n: number }[];
  people: { emailsGiven: number; accounts: number };
  /** People who asked for the iPhone beta, newest first (for the owner to invite). */
  beta: { email: string; device: string; wants: string; source: string; at: string }[];
}

/** The last `span` days as JSON for the owner's dashboard (the same counters as siteReport). */
export async function siteStats(store: QuotaStore, now = new Date(), span = 30): Promise<SiteStats> {
  const days_ = Array.from({ length: span }, (_, i) => dayKey(new Date(now.getTime() - (span - 1 - i) * 86_400_000)));
  const totals: Record<string, number> = {};
  const daily: Record<string, Record<string, number>> = {};
  const keyActions: SiteStats["keyActions"] = [];
  if (!store.scanPrefix) return { days: days_, totals, daily, keyActions, people: { emailsGiven: 0, accounts: 0 }, beta: [] };
  for (const { key, count } of await store.scanPrefix("site_")) {
    const match = /^site_(\d{4}-\d{2}-\d{2})_(.+)$/.exec(key);
    if (!match || !days_.includes(match[1])) continue;
    const [, day, name] = match;
    if (name.startsWith("t|")) {
      const [, hhmm, channel, action, source, kind] = name.split("|");
      if (kind) keyActions.push({ day, time: `${hhmm.slice(0, 2)}:${hhmm.slice(2)}`, channel, action, source, device: kind, n: count });
      continue;
    }
    totals[name] = (totals[name] ?? 0) + count;
    if (DAILY.test(name)) (daily[name] ??= {})[day] = count;
  }
  keyActions.sort((a, b) => `${b.day}${b.time}`.localeCompare(`${a.day}${a.time}`));
  const emailsGiven = (await store.scanPrefix("signup_")).length;
  const accounts = (await store.scanPrefix("account_")).filter((row) => !row.key.startsWith("accountinstall_")).length;
  const beta: SiteStats["beta"] = [];
  for (const { key } of (await store.scanPrefix("betasignup_")).slice(0, 300)) {
    const record = await store.getRecord(key);
    if (!record || typeof record.email !== "string") continue;
    beta.push({ email: record.email, device: String(record.device ?? ""), wants: String(record.wants ?? ""),
                source: String(record.source ?? ""), at: String(record.firstAt ?? "") });
  }
  beta.sort((a, b) => b.at.localeCompare(a.at));
  return { days: days_, totals, daily, keyActions: keyActions.slice(0, 60), people: { emailsGiven, accounts }, beta };
}
