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
};

/** The last `span` days of website numbers, as plain text for the owner. */
export async function siteReport(store: QuotaStore, now = new Date(), span = 7): Promise<string> {
  if (!store.scanPrefix) return "Site analytics need the DynamoDB store.";
  const dates = Array.from({ length: span }, (_, i) => dayKey(new Date(now.getTime() - i * 86_400_000)));
  const totals = new Map<string, number>();
  const perDay = new Map<string, number>();
  for (const { key, count } of await store.scanPrefix("site_")) {
    const match = /^site_(\d{4}-\d{2}-\d{2})_(.+)$/.exec(key);
    if (!match || !dates.includes(match[1])) continue;
    totals.set(match[2], (totals.get(match[2]) ?? 0) + count);
    if (match[2] === "visitors") perDay.set(match[1], count);
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
  const lines = [
    `notchman.app, last ${span} days (${dates[dates.length - 1]} to ${dates[0]}, UTC)`,
    "",
    `Visitors: ${visitors.toLocaleString("en-US")}   Page views: ${pageViews.toLocaleString("en-US")}`,
    `Downloads started: ${downloads}${pct(downloads)}   GitHub clicks: ${get("click_github")}${pct(get("click_github"))}   Checkouts completed (thank-you page): ${get("view_thanks")}`,
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
    "No cookies and no personal data: only daily counts. Downloads count clicks on the download buttons.",
  ];
  return lines.join("\n");
}
