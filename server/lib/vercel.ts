import type { VercelRequest, VercelResponse } from "@vercel/node";
import type { Result } from "./handlers.js";

/** Adapts a handler to a Vercel function: POST + JSON only. */
export function route(handler: (body: unknown) => Promise<Result>) {
  return async (req: VercelRequest, res: VercelResponse) => {
    res.setHeader("Cache-Control", "no-store");
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }
    try {
      const result = await handler(req.body);
      res.status(result.status).json(result.body);
    } catch (error) {
      console.error(error);
      res.status(500).json({ error: "internal" });
    }
  };
}

export function freeDailyCap(): number {
  return Number(process.env.FREE_DAILY_GLOBAL_CAP ?? 5_000);
}
