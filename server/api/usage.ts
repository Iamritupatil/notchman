import { handleUsage } from "../lib/handlers.js";
import { usageStore } from "../lib/usage.js";
import { route } from "../lib/vercel.js";

export default route((body) => handleUsage(body, { store: usageStore() }));
