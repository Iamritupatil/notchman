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

export function device(userAgent: string | undefined): "phone" | "tablet" | "desktop" {
  const ua = userAgent ?? "";
  if (/iPad|Tablet/i.test(ua)) return "tablet";
  return /Mobi|iPhone|Android/i.test(ua) ? "phone" : "desktop";
}

const BOTS = /bot|crawl|spider|slurp|preview|facebookexternalhit|headless|lighthouse|pingdom|uptime/i;

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
      }
      break;
    }
    case "click":
    case "faq": {
      const what = label(event.t);
      if (what) await count(`${event.e}_${what}`);
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
  const lines = [
    `notchman.app, last ${span} days (${dates[dates.length - 1]} to ${dates[0]}, UTC)`,
    "",
    `Visitors: ${visitors.toLocaleString("en-US")}   Page views: ${pageViews.toLocaleString("en-US")}`,
    `Downloads: ${exactDownloads} (by ${get("dlpeople_windows") + get("dlpeople_mac") + get("dlpeople_mac-intel")} people)   Download clicks: ${downloads}${pct(downloads)}${phoneTaps ? `, plus ${phoneTaps} on phones` : ""}   GitHub clicks: ${get("click_github")}${pct(get("click_github"))}`,
    `Automated link checks (scanners, not counted as downloads): ${get("dlauto")}`,
    `Desktop app: ${get("appnew_windows") + get("appnew_mac")} new installs, opened by ${get("appactive_windows") + get("appactive_mac")} (people-days)   Checkouts completed (thank-you page): ${get("view_thanks")}`,
    "",
    "Downloads per day (from the website's download links: started / people):",
    ...dates.slice().reverse().map((d) => {
      const parts = Object.keys(DOWNLOAD_FILES).map((p) => `${p} ${perDayCount(d, `dl_${p}`)}/${perDayCount(d, `dlpeople_${p}`)}`);
      return `  ${d}  ${parts.join("   ")}`;
    }),
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
    `  ${get("copy_commands").toLocaleString("en-US").padStart(6)}  Copied the Community commands`,
    "",
    "How far down they scrolled:",
    ...[25, 50, 75, 100].map((d) => `  ${get(`scroll_${d}`).toLocaleString("en-US").padStart(6)}  reached ${d}%`),
    "",
    "Time on the page:", ...(group("time_").length ? group("time_") : ["  (none yet)"]),
    "",
    "FAQ questions opened:", ...(group("faq_", {}, 15).length ? group("faq_", {}, 15) : ["  (none yet)"]),
    "",
    "No cookies and no personal data: only daily counts. Downloads are counted when the website's download links are used; app numbers come from the desktop app's daily hello.",
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
                                     visitor: { ip?: string; userAgent?: string; pepper?: string; automated?: boolean },
                                     now = new Date()): Promise<void> {
  if (!(platform in DOWNLOAD_FILES)) return;
  const day = dayKey(now);
  const keep = days(400, now);
  // Link checkers and scanners: counted apart, never as downloads.
  if (visitor.automated || BOTS.test(visitor.userAgent ?? "")) {
    await store.consume(`site_${day}_dlauto`, ALL, keep);
    return;
  }
  await store.consume(`site_${day}_dl_${platform}`, ALL, keep);
  const person = createHash("sha256").update(`${day}|${visitor.pepper ?? ""}|${visitor.ip ?? ""}|${visitor.userAgent ?? ""}`).digest("hex").slice(0, 32);
  const first = await store.consume(`sitedl_${person}_${platform}`, 1, days(2, now));
  if (first.allowed) await store.consume(`site_${day}_dlpeople_${platform}`, ALL, keep);
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
