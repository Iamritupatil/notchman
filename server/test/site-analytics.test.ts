import { describe, expect, it } from "vitest";
import { route } from "../src/lambda.js";
import { MemoryQuotaStore } from "../src/quota.js";
import { device, label, recordSiteEvent, referrerDomain, siteReport } from "../src/site-analytics.js";

const NOW = new Date(Date.UTC(2026, 9, 9, 12, 0));
const CHROME = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/141 Safari/537.36";
const IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) Mobile/15E148 Safari/604.1";

describe("website analytics (cookieless)", () => {
  it("counts visitors once a day, with where they came from and their device", async () => {
    const store = new MemoryQuotaStore();
    const alice = { ip: "203.0.113.1", userAgent: CHROME, pepper: "p" };
    const bob = { ip: "198.51.100.2", userAgent: IPHONE, pepper: "p" };
    await recordSiteEvent(store, { e: "view", p: "/", r: "https://www.google.com/search?q=notchman", u: "youtube" }, alice, NOW);
    await recordSiteEvent(store, { e: "view", p: "/privacy", r: "https://notchman.app/" }, alice, NOW);
    await recordSiteEvent(store, { e: "view", p: "/" }, bob, NOW);
    expect(await store.count("site_2026-10-09_visitors")).toBe(2);
    expect(await store.count("site_2026-10-09_view_home")).toBe(2);
    expect(await store.count("site_2026-10-09_view_privacy")).toBe(1);
    expect(await store.count("site_2026-10-09_ref_google.com")).toBe(1);
    expect(await store.count("site_2026-10-09_ref_direct")).toBe(1);
    expect(await store.count("site_2026-10-09_utm_youtube")).toBe(1);
    expect(await store.count("site_2026-10-09_device_phone")).toBe(1);
  });

  it("keeps only safe labels, ignores bots and limits bursts", async () => {
    expect(label("Download Mac!<script>")).toBe("download_mac_script");
    expect(referrerDomain("javascript:alert(1)")).toBeUndefined();
    expect(device(IPHONE)).toBe("phone");
    const store = new MemoryQuotaStore();
    expect(await recordSiteEvent(store, { e: "view" }, { userAgent: "Googlebot/2.1" }, NOW)).toEqual([]);
    const spammer = { ip: "192.0.2.9", userAgent: CHROME };
    for (let i = 0; i < 70; i++) await recordSiteEvent(store, { e: "click", t: "github" }, spammer, NOW);
    expect(await store.count("site_2026-10-09_click_github")).toBe(60);
  });

  it("turns the counters into a weekly report", async () => {
    const store = new MemoryQuotaStore();
    const v = (ip: string) => ({ ip, userAgent: CHROME, pepper: "p" });
    for (const ip of ["1.1.1.1", "2.2.2.2", "3.3.3.3", "4.4.4.4"]) await recordSiteEvent(store, { e: "view", p: "/", r: "https://x.com/post" }, v(ip), NOW);
    await recordSiteEvent(store, { e: "click", t: "download_windows" }, v("1.1.1.1"), NOW);
    await recordSiteEvent(store, { e: "click", t: "github" }, v("2.2.2.2"), NOW);
    await recordSiteEvent(store, { e: "copy", t: "commands" }, v("2.2.2.2"), NOW);
    await recordSiteEvent(store, { e: "scroll", d: 50 }, v("2.2.2.2"), NOW);
    await recordSiteEvent(store, { e: "time", d: 95 }, v("2.2.2.2"), NOW);
    await recordSiteEvent(store, { e: "faq", t: "is_notchman_open_source" }, v("3.3.3.3"), NOW);
    await recordSiteEvent(store, { e: "view", p: "/thanks" }, v("3.3.3.3"), NOW);
    const report = await siteReport(store, NOW);
    expect(report).toContain("Visitors: 4   Page views: 5");
    expect(report).toContain("Download clicks: 1 (25% of visitors)");
    expect(report).toContain("Checkouts completed (thank-you page): 1");
    expect(report).toMatch(/4 {2}x\.com/);
    expect(report).toContain("Download for Windows");
    expect(report).toMatch(/1 {2}Copied the Community commands/);
    expect(report).toMatch(/1 {2}reached 50%/);
    expect(report).toMatch(/1 {2}1-3min/);
    expect(report).toContain("is notchman open source");
  });

  it("answers the browser's beacon without needing an install ID", async () => {
    const store = new MemoryQuotaStore();
    const response = await route({
      rawPath: "/event", body: JSON.stringify({ e: "click", t: "hero_download" }), isBase64Encoded: false,
      headers: { "user-agent": CHROME }, requestContext: { http: { method: "POST", sourceIp: "203.0.113.5" } },
    } as never, { deps: { store } as never });
    expect(response.statusCode).toBe(204);
    expect(await store.count(`site_${new Date().toISOString().slice(0, 10)}_click_hero_download`)).toBe(1);
  });
});

describe("downloads and desktop app use", () => {
  const request = (method: string, path: string, headers: Record<string, string> = {}, body = "{}") => ({
    rawPath: path, body, isBase64Encoded: false, headers,
    requestContext: { http: { method, sourceIp: "203.0.113.20" } },
  }) as never;
  const today = () => new Date().toISOString().slice(0, 10);

  it("counts a download from the website and sends the browser to the installer", async () => {
    const store = new MemoryQuotaStore();
    const response = await route(request("GET", "/dl/windows", { "user-agent": CHROME }), { deps: { store } as never });
    expect(response.statusCode).toBe(302);
    expect(response.headers?.location).toBe("https://dy7adwloxsruv.cloudfront.net/latest/Notchman-Setup.exe");
    await route(request("GET", "/dl/windows", { "user-agent": CHROME }), { deps: { store } as never });
    expect(await store.count(`site_${today()}_dl_windows`)).toBe(2);
    expect(await store.count(`site_${today()}_dlpeople_windows`)).toBe(1);
    expect((await route(request("GET", "/dl/linux"), { deps: { store } as never })).statusCode).toBe(404);
  });

  it("counts new installs once and opens once a day", async () => {
    const store = new MemoryQuotaStore();
    const hello = (install: string, platform: string) => route(request("POST", "/hello", { "x-notchman-install": install },
      JSON.stringify({ platform, version: "0.1.34", edition: "pro" })), { deps: { store } as never });
    const a = "11111111-1111-4111-8111-111111111111";
    const b = "22222222-2222-4222-8222-222222222222";
    expect((await hello(a, "win32")).statusCode).toBe(200);
    await hello(a, "win32");
    await hello(b, "darwin");
    expect(await store.count(`site_${today()}_appnew_windows`)).toBe(1);
    expect(await store.count(`site_${today()}_appactive_windows`)).toBe(1);
    expect(await store.count(`site_${today()}_appnew_mac`)).toBe(1);
    expect(await store.count(`site_${today()}_appversion_0.1.34`)).toBe(2);
    const report = await siteReport(store, new Date());
    expect(report).toMatch(/windows 1\/1 {3}mac 1\/1/);
  });
});
