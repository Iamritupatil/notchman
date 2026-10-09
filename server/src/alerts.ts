import { PublishCommand, SNSClient } from "@aws-sdk/client-sns";
import { dayKey, days, monthKey, type QuotaStore } from "./quota.js";

/**
 * Email alerts to the owner (an SNS topic with an email subscription, see
 * template.yaml): when the Notchman voice (ElevenLabs) nears this month's
 * budget, when free users hit the daily free cap, and when the ElevenLabs
 * balance runs low. Each alert is sent once (per month or per day).
 */

export type Notify = (subject: string, message: string) => Promise<void>;

let sns: SNSClient | undefined;
export const snsNotify: Notify = async (subject, message) => {
  const topic = process.env.ALERT_TOPIC_ARN;
  if (!topic) return;
  sns ??= new SNSClient({});
  await sns.send(new PublishCommand({ TopicArn: topic, Subject: subject.slice(0, 99), Message: message }));
};

/** Sends an alert the first time `key` is seen. Never throws. Returns true if it was sent now. */
export async function alertOnce(store: QuotaStore, key: string, subject: string, message: string,
                                expiresAt: Date, notify: Notify = snsNotify): Promise<boolean> {
  try {
    const first = await store.consume(`alert_${key}`, 1, expiresAt);
    if (!first.allowed) return false;
    await notify(subject, message);
    console.log("alert sent", key);
    return true;
  } catch (error) {
    console.warn("alert failed", key, error instanceof Error ? error.message : error);
    return false;
  }
}

const ALL = Number.MAX_SAFE_INTEGER;

/** Counts Notchman-voice (ElevenLabs) characters made this month, for free and paying users. */
export async function countVoice(store: QuotaStore, characters: number, paid: boolean, now: Date): Promise<void> {
  await store.consume(`elmonth_${paid ? "paid" : "free"}_${monthKey(now)}`, ALL, days(70, now), characters);
}

export interface UsageCheckOptions {
  /** ElevenLabs characters a month you're happy to spend (your plan's credits). */
  budget: number;
  notify?: Notify;
  /** ElevenLabs credits left, if the API key may read it. */
  balance?: () => Promise<number | undefined>;
  /** Paying desktop subscribers (Dodo), if it can be read. */
  subscribers?: () => Promise<{ pro: number; proplus: number } | undefined>;
}

const THRESHOLDS = [50, 80, 95];

/** This month's Notchman-voice use, in words for the email. */
export async function usageReport(store: QuotaStore, now: Date, options: UsageCheckOptions) {
  const month = monthKey(now);
  const free = await store.count(`elmonth_free_${month}`);
  const paid = await store.count(`elmonth_paid_${month}`);
  const used = free + paid;
  const percent = options.budget > 0 ? Math.round((used / options.budget) * 100) : 0;
  const balance = await options.balance?.().catch(() => undefined);
  const subscribers = await options.subscribers?.().catch(() => undefined);
  const n = (value: number) => value.toLocaleString("en-US");
  const lines = [
    `Notchman voice (ElevenLabs) in ${month}: ${n(used)} of your ${n(options.budget)}-character budget (${percent}%).`,
    `- Free users: ${n(free)} characters`,
    `- Paying users: ${n(paid)} characters`,
    balance === undefined
      ? "- ElevenLabs credits left: unknown (give the ElevenLabs API key the \"User: Read\" permission so Notchman can see it)"
      : `- ElevenLabs credits left: ${n(balance)}`,
    subscribers
      ? `- Paying desktop subscribers (Dodo): ${subscribers.pro} Pro ($${(subscribers.pro * 4.99).toFixed(2)}/mo) and ${subscribers.proplus} Pro+ ($${(subscribers.proplus * 9.99).toFixed(2)}/mo)`
      : "- Paying desktop subscribers (Dodo): couldn't be read right now",
    "",
    "When you need more, top up at https://elevenlabs.io/app/subscription. Free users are also capped per day, and they switch to the free voice when the cap is reached, so nothing breaks.",
  ];
  return { month, used, free, paid, percent, balance, text: lines.join("\n") };
}

/** Hourly: emails when this month's Notchman-voice use crosses 50%, 80% and 95% of the budget, and when credits run low. */
export async function usageCheck(store: QuotaStore, now: Date, options: UsageCheckOptions): Promise<{ sent: string[] }> {
  const report = await usageReport(store, now, options);
  const sent: string[] = [];
  const crossed = THRESHOLDS.filter((t) => report.percent >= t);
  if (crossed.length) {
    const highest = crossed[crossed.length - 1];
    // A jump straight past 50% sends only the highest alert; the lower ones are marked done.
    for (const lower of crossed.slice(0, -1)) await store.consume(`alert_budget_${report.month}_${lower}`, 1, days(70, now));
    const subject = `Notchman: ElevenLabs voice at ${report.percent}% of this month's budget`;
    if (await alertOnce(store, `budget_${report.month}_${highest}`, subject, report.text, days(70, now), options.notify)) {
      sent.push(`budget ${highest}%`);
    }
  }
  if (report.balance !== undefined && report.balance < 3000) {
    const subject = `Notchman: only ${report.balance.toLocaleString("en-US")} ElevenLabs credits left`;
    if (await alertOnce(store, `balance_${dayKey(now)}`, subject, report.text, days(2, now), options.notify)) sent.push("low balance");
  }
  return { sent };
}
