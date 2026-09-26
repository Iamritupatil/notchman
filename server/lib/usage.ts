import { Redis } from "@upstash/redis";

/** Counter storage. Redis in production; in-memory for tests and local runs. */
export interface UsageStore {
  increment(key: string, ttlSeconds: number): Promise<number>;
  decrement(key: string): Promise<number>;
  get(key: string): Promise<number>;
}

export class MemoryUsageStore implements UsageStore {
  private counts = new Map<string, number>();
  async increment(key: string): Promise<number> {
    const next = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, next);
    return next;
  }
  async decrement(key: string): Promise<number> {
    const next = Math.max(0, (this.counts.get(key) ?? 0) - 1);
    this.counts.set(key, next);
    return next;
  }
  async get(key: string): Promise<number> {
    return this.counts.get(key) ?? 0;
  }
}

export class RedisUsageStore implements UsageStore {
  constructor(private redis: Redis) {}
  async increment(key: string, ttlSeconds: number): Promise<number> {
    const value = await this.redis.incr(key);
    if (value === 1) await this.redis.expire(key, ttlSeconds);
    return value;
  }
  async decrement(key: string): Promise<number> {
    return this.redis.decr(key);
  }
  async get(key: string): Promise<number> {
    return Number((await this.redis.get<number>(key)) ?? 0);
  }
}

let shared: UsageStore | undefined;

/** Uses Upstash Redis when its env vars are present (Vercel Marketplace integration). */
export function usageStore(): UsageStore {
  if (shared) return shared;
  const url = process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN ?? process.env.KV_REST_API_TOKEN;
  shared = url && token ? new RedisUsageStore(new Redis({ url, token })) : new MemoryUsageStore();
  return shared;
}

export function monthKey(date = new Date()): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function dayKey(date = new Date()): string {
  return `${monthKey(date)}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

const MONTH_TTL = 40 * 24 * 3600;
const DAY_TTL = 2 * 24 * 3600;

export interface QuotaResult {
  allowed: boolean;
  used: number;
  limit: number;
  reason?: "monthly_limit" | "free_capacity";
}

/**
 * Reserves one TL;DR for this account in the current month. Call `release` if
 * the summary then fails, so users aren't charged for errors.
 *
 * `freeDailyCap` bounds total free-tier spend per day across all users, so
 * abuse (e.g. scripted fake installs) can never run up an unbounded bill.
 */
export async function reserve(
  store: UsageStore, accountKey: string, limit: number,
  options: { isFree: boolean; freeDailyCap?: number; now?: Date } = { isFree: true },
): Promise<QuotaResult> {
  const now = options.now ?? new Date();
  const key = `usage:${accountKey}:${monthKey(now)}`;
  const used = await store.increment(key, MONTH_TTL);
  if (used > limit) {
    await store.decrement(key);
    return { allowed: false, used: limit, limit, reason: "monthly_limit" };
  }
  if (options.isFree && options.freeDailyCap) {
    const globalKey = `free-global:${dayKey(now)}`;
    const total = await store.increment(globalKey, DAY_TTL);
    if (total > options.freeDailyCap) {
      await store.decrement(globalKey);
      await store.decrement(key);
      return { allowed: false, used: used - 1, limit, reason: "free_capacity" };
    }
  }
  return { allowed: true, used, limit };
}

export async function release(store: UsageStore, accountKey: string, isFree: boolean, now = new Date()) {
  await store.decrement(`usage:${accountKey}:${monthKey(now)}`);
  if (isFree) await store.decrement(`free-global:${dayKey(now)}`);
}

export async function currentUsage(store: UsageStore, accountKey: string, now = new Date()): Promise<number> {
  return store.get(`usage:${accountKey}:${monthKey(now)}`);
}
