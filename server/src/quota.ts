/**
 * Atomic counters for monthly allowances, per-minute rate limits and the
 * daily beta allowance. DynamoDB in production (see dynamo.ts); in-memory for tests.
 */
export interface QuotaStore {
  /** Adds `amount` (default 1) to `key` if the total stays within `limit`. Returns the count after the attempt. */
  consume(key: string, limit: number, expiresAt: Date, amount?: number): Promise<{ allowed: boolean; count: number }>;
  refund(key: string, amount?: number): Promise<void>;
  count(key: string): Promise<number>;
  /** A small JSON record (e.g. a subscription), or null. */
  getRecord(key: string): Promise<Record<string, unknown> | null>;
  putRecord(key: string, value: Record<string, unknown>, expiresAt: Date): Promise<void>;
  /** Every counter whose key starts with `prefix` (small tables only: for reports). */
  scanPrefix?(prefix: string): Promise<{ key: string; count: number }[]>;
}

export class MemoryQuotaStore implements QuotaStore {
  private counts = new Map<string, number>();
  async consume(key: string, limit: number, _expiresAt?: Date, amount = 1) {
    const current = this.counts.get(key) ?? 0;
    if (current + amount > limit) return { allowed: false, count: current };
    this.counts.set(key, current + amount);
    return { allowed: true, count: current + amount };
  }
  async refund(key: string, amount = 1) {
    this.counts.set(key, Math.max(0, (this.counts.get(key) ?? 0) - amount));
  }
  async count(key: string) {
    return this.counts.get(key) ?? 0;
  }
  private records = new Map<string, Record<string, unknown>>();
  async getRecord(key: string) {
    return this.records.get(key) ?? null;
  }
  async putRecord(key: string, value: Record<string, unknown>) {
    this.records.set(key, value);
  }
  async scanPrefix(prefix: string) {
    return [...this.counts].filter(([key]) => key.startsWith(prefix)).map(([key, count]) => ({ key, count }));
  }
}

export function monthKey(date = new Date()): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function dayKey(date = new Date()): string {
  return `${monthKey(date)}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

export function minuteKey(date = new Date()): string {
  return `${dayKey(date)}T${String(date.getUTCHours()).padStart(2, "0")}${String(date.getUTCMinutes()).padStart(2, "0")}`;
}

export const days = (n: number, from = new Date()) => new Date(from.getTime() + n * 86_400_000);
