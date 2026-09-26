import { handleTLDR } from "../lib/handlers.js";
import { usageStore } from "../lib/usage.js";
import { freeDailyCap, route } from "../lib/vercel.js";

export default route((body) => handleTLDR(body, { store: usageStore(), freeDailyCap: freeDailyCap() }));
