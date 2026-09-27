import type { Firestore } from "firebase-admin/firestore";

/**
 * Atomic counters for monthly allowances, per-minute rate limits and the
 * daily free-tier safety cap. Firestore in production; in-memory for tests.
 */
export interface QuotaStore {
  /** Adds one to `key` if it's below `limit`. Returns the count after the attempt. */
  consume(key: string, limit: number, expiresAt: Date): Promise<{ allowed: boolean; count: number }>;
  refund(key: string): Promise<void>;
  count(key: string): Promise<number>;
}

export class MemoryQuotaStore implements QuotaStore {
  private counts = new Map<string, number>();
  async consume(key: string, limit: number) {
    const current = this.counts.get(key) ?? 0;
    if (current >= limit) return { allowed: false, count: current };
    this.counts.set(key, current + 1);
    return { allowed: true, count: current + 1 };
  }
  async refund(key: string) {
    this.counts.set(key, Math.max(0, (this.counts.get(key) ?? 0) - 1));
  }
  async count(key: string) {
    return this.counts.get(key) ?? 0;
  }
}

/**
 * One document per counter in the `quotas` collection (clients can't touch it;
 * see firestore.rules). `expiresAt` drives a Firestore TTL policy so old
 * counters are deleted automatically.
 */
export class FirestoreQuotaStore implements QuotaStore {
  constructor(private db: Firestore) {}

  private ref(key: string) {
    return this.db.collection("quotas").doc(key.replace(/[/]/g, "_"));
  }

  async consume(key: string, limit: number, expiresAt: Date) {
    const ref = this.ref(key);
    return this.db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const current = (snapshot.get("count") as number | undefined) ?? 0;
      if (current >= limit) return { allowed: false, count: current };
      tx.set(ref, { count: current + 1, expiresAt }, { merge: true });
      return { allowed: true, count: current + 1 };
    });
  }

  async refund(key: string) {
    const ref = this.ref(key);
    await this.db.runTransaction(async (tx) => {
      const current = ((await tx.get(ref)).get("count") as number | undefined) ?? 0;
      if (current > 0) tx.update(ref, { count: current - 1 });
    });
  }

  async count(key: string) {
    return ((await this.ref(key).get()).get("count") as number | undefined) ?? 0;
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
