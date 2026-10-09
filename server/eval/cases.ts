/**
 * TL;DR quality cases: realistic texts and the facts a good TL;DR must keep.
 * Each fact passes if the summary contains any of its alternatives (case and
 * thousands separators ignored). Run with `npm run eval` (needs GROQ_API_KEY).
 */
export interface EvalCase {
  name: string;
  text: string;
  facts: { fact: string; any: string[] }[];
}

export const CASES: EvalCase[] = [
  {
    name: "Tech launch article",
    text: `Nimbus Labs today announced Nimbus 3, the newest version of its AI model for developers, and it changes the math for anyone building chatbots or coding tools. The company says Nimbus 3 is about 40% cheaper than Nimbus 2 while scoring slightly higher on its internal coding benchmark, 71.2% versus 68.9%. Pricing starts at $20 per month for the Starter plan, which includes 2 million tokens; after that it costs $0.80 per million input tokens and $3.20 per million output tokens.

The model can now read up to 256,000 tokens at once, double the previous 128,000, which means an entire mid-sized codebase or a 400-page contract fits into a single request. Response times also improved: the median first token now arrives in 310 milliseconds, down from 520.

There are trade-offs. Two older parameters, logit_bias and best_of, are no longer supported, so apps that rely on them will break if they switch without changes. Image input is still in beta and limited to the US and EU regions for now, with India and Japan "planned for early next year," according to the company.

Existing customers have time to move. Nimbus 2 will keep working until March 14, 2027, after which requests to it will fail. Nimbus Labs recommends testing the new model on a staging environment first because outputs can differ in format, especially for JSON responses. Enterprise customers who sign a 12-month contract before December 31 get a 15% discount and a dedicated support engineer.

Analysts were mostly positive but cautious. "The price cut is real, but the benchmark is the company's own," said Priya Raman of Arc Research, noting that independent tests have not been published yet.`,
    facts: [
      { fact: "Nimbus 3 launched", any: ["nimbus 3"] },
      { fact: "40% cheaper", any: ["40%", "40 percent"] },
      { fact: "benchmark 71.2 vs 68.9", any: ["71.2"] },
      { fact: "$20 a month Starter", any: ["$20", "20 dollars"] },
      { fact: "256,000 tokens context", any: ["256,000", "256000", "256k", "256 thousand"] },
      { fact: "logit_bias and best_of removed", any: ["logit_bias", "logit bias"] },
      { fact: "Nimbus 2 ends March 14, 2027", any: ["march 14", "14 march"] },
      { fact: "test on staging first", any: ["staging"] },
      { fact: "15% enterprise discount", any: ["15%", "15 percent"] },
      { fact: "benchmark is the company's own / not independent", any: ["own benchmark", "company's own", "independent", "its own"] },
      { fact: "image input beta US/EU only", any: ["beta"] },
    ],
  },
  {
    name: "Work email with action items",
    text: `Hi team,

Quick update after this morning's call with the client, sorry for the long mail but please read till the end because there are a few things each of you needs to do.

First, the launch review has moved. It was on Tuesday but the client's CFO can't make it, so it's now on Thursday, 23 October, at 3:30 pm IST, same Google Meet link. Please block your calendars.

Second, budget. They approved ₹4.5 lakh for phase two, not the ₹6 lakh we asked for. The difference means we're dropping the Android widget from this phase; it moves to phase three. Everything else stays in scope.

Third, deadlines. The design files are due on 20 October. The staging build has to be ready by 22 October so they can click through it before the review. Anything later and we lose the slot.

Action items:
- Meera: send the revised timeline to the client by tomorrow, 6 pm.
- Arjun: update the estimate sheet to match the ₹4.5 lakh number and share it with finance.
- Kabir: freeze the API changes by Monday; no new endpoints after that.

One more thing: they asked whether we can add Hindi support. I said we'd check. It is not approved yet, so please don't start on it.

Thanks,
Ritika`,
    facts: [
      { fact: "review moved to Thursday 23 Oct 3:30 pm", any: ["3:30", "330", "3.30"] },
      { fact: "on Thursday / 23 October", any: ["thursday", "23 october", "october 23", "23rd"] },
      { fact: "₹4.5 lakh approved", any: ["4.5 lakh", "4.5"] },
      { fact: "asked ₹6 lakh", any: ["6 lakh", "₹6"] },
      { fact: "Android widget dropped to phase three", any: ["android"] },
      { fact: "design files due 20 Oct", any: ["20 october", "october 20", "20th"] },
      { fact: "staging ready by 22 Oct", any: ["22 october", "october 22", "22nd"] },
      { fact: "Meera: revised timeline by tomorrow 6 pm", any: ["meera"] },
      { fact: "Arjun: update estimate sheet", any: ["arjun"] },
      { fact: "Kabir: freeze API changes by Monday", any: ["kabir"] },
      { fact: "Hindi support not approved, don't start", any: ["hindi"] },
    ],
  },
  {
    name: "Founder LinkedIn post",
    text: `14 months ago I quit my job with ₹3 lakh in savings and an idea everyone called "too small."

Last week we closed a $2.1M seed round led by Peak Ventures, with Lightspeed and 11 angels joining.

Here's what nobody tells you about the first year. 👇

1. Revenue beats a deck. We didn't pitch anyone until we had 40 paying customers. By then we were at $18k in monthly revenue, growing 22% month over month, and the conversations changed completely. Investors stopped asking "will anyone pay?" and started asking "how fast can you grow?"

2. Hire slower than you want. We made 3 hires in the first year and one of them didn't work out. That mistake cost us roughly 4 months. Now nobody joins without a paid two-week trial project.

3. Churn is the real number. Our churn was 9% a month in the spring, which would have killed us. We fixed onboarding, added a 15-minute setup call for every new customer, and brought it down to 2.5%.

What's next: we're hiring 6 engineers in Bengaluru and launching in Southeast Asia in Q1.

If you're building something people say is too small, keep going. Small markets have a way of getting big. ♻️ Repost if this helped someone in your network.`,
    facts: [
      { fact: "$2.1M seed", any: ["2.1"] },
      { fact: "led by Peak Ventures", any: ["peak ventures", "peak"] },
      { fact: "14 months", any: ["14 months"] },
      { fact: "40 paying customers before pitching", any: ["40 paying", "40 customers", "40 clients"] },
      { fact: "$18k monthly revenue", any: ["18k", "18,000", "18000", "$18"] },
      { fact: "22% monthly growth", any: ["22%", "22 percent"] },
      { fact: "hire slowly: paid two-week trial", any: ["trial"] },
      { fact: "churn 9% to 2.5%", any: ["2.5%", "2.5 percent"] },
      { fact: "setup call fixed churn", any: ["setup call", "onboarding"] },
      { fact: "hiring 6 engineers / SE Asia Q1", any: ["6 engineers", "six engineers", "southeast asia"] },
    ],
  },
  {
    name: "AI answer: database choice",
    text: `Short answer: for your app, use PostgreSQL, and keep MongoDB only if you later find a part of the data that truly has no fixed shape.

Here's the reasoning.

1. Your data is relational. Users have orders, orders have items, items belong to products. These are joins, and PostgreSQL handles joins natively and efficiently. In MongoDB you'd either embed documents (which duplicates data and makes updates painful) or do multiple queries and join in your app code.

2. You need transactions. When a payment succeeds you update the order, decrease stock and write a ledger entry, and all three must happen or none. PostgreSQL has had full ACID transactions for decades. MongoDB supports multi-document transactions since version 4.0, but they're slower and have limits, such as a default 60-second lifetime.

3. You still get flexibility. PostgreSQL's JSONB column type stores schemaless JSON and can index it with GIN indexes, so product attributes that vary per category can live in one JSONB column without a separate database.

4. Scale is not a concern yet. You mentioned about 50,000 users. A single PostgreSQL instance on a $50/month server handles that comfortably; teams run millions of users on Postgres with read replicas.

When MongoDB would be the better choice: if most of your data were documents with unpredictable structure, like event logs or user-generated forms, or if you needed built-in horizontal sharding from day one.

Caveats: whichever you choose, set up automated daily backups and test restoring them at least once a month. And don't pick based on what's trendy; migrating databases later is expensive, often weeks of work.`,
    facts: [
      { fact: "recommendation: PostgreSQL", any: ["postgres"] },
      { fact: "data is relational / joins", any: ["join", "relational"] },
      { fact: "needs transactions (ACID)", any: ["transaction", "acid"] },
      { fact: "Mongo transactions since 4.0 but slower, 60-second limit", any: ["60-second", "60 second", "60 seconds", "4.0", "slower"] },
      { fact: "JSONB for flexible attributes", any: ["jsonb"] },
      { fact: "50,000 users fine on one $50 server", any: ["50,000", "50000", "50 thousand", "$50"] },
      { fact: "when Mongo is better: unpredictable docs / sharding", any: ["shard", "unpredictable", "event log", "logs"] },
      { fact: "daily backups, test restore monthly", any: ["backup"] },
      { fact: "migrating later is expensive", any: ["migrat"] },
    ],
  },
  {
    name: "Policy announcement",
    text: `Important changes to our refund and subscription policy

Starting 1 November 2026, we're updating how refunds and plan changes work for all CloudNest customers. Please read this carefully, because some of these changes affect you even if you don't do anything.

Refund window. The refund window for annual plans increases from 14 days to 30 days after purchase. Monthly plans can still be refunded within 7 days, but only once per account.

Exceptions. Refunds are not available for add-on storage purchases, for domains, or for accounts suspended for violating our terms. Partial refunds for unused months on annual plans are no longer offered after the 30-day window.

Price change. The Business plan goes from $12 to $15 per user per month for new customers. Existing Business customers keep their current price until their next renewal after 1 February 2027.

Auto-renewal. Annual plans will now renew automatically by default. We'll email you 15 days before every renewal, and you can turn auto-renewal off at any time in Settings → Billing.

Data after cancellation. When you cancel, your files are kept for 60 days (previously 90) and then permanently deleted. Download anything you need before that.

If you have questions, contact support@cloudnest.example. If you don't agree with these changes, you can cancel before 1 November and receive a prorated refund for the remainder of your current annual term.`,
    facts: [
      { fact: "effective 1 November 2026", any: ["1 november", "november 1", "november first", "1st november"] },
      { fact: "annual refund window 14 → 30 days", any: ["30 days"] },
      { fact: "monthly: 7 days, once per account", any: ["7 days", "seven days"] },
      { fact: "no refunds for add-on storage, domains, suspended", any: ["domain", "storage", "suspend"] },
      { fact: "Business $12 → $15 for new customers", any: ["$15", "15 dollars"] },
      { fact: "existing keep price until renewal after 1 Feb 2027", any: ["february", "feb"] },
      { fact: "auto-renewal on by default, email 15 days before", any: ["15 days", "auto-renew", "renew automatically", "automatically renew"] },
      { fact: "files kept 60 days (was 90) then deleted", any: ["60 days"] },
      { fact: "cancel before 1 Nov for prorated refund", any: ["prorated", "pro-rated", "pro rata"] },
    ],
  },
];

/** Whether the summary mentions one of a fact's alternatives. */
export function mentions(summary: string, alternatives: string[]): boolean {
  const plain = (t: string) => t.toLowerCase()
    .replace(/[\u00A0\u2007\u2009\u202F]/g, " ").replace(/[\u2010\u2011\u2012\u2013]/g, "-")
    .replace(/(\d) +%/g, "$1%").replace(/(\d),(?=\d{3})/g, "$1").replace(/[’']/g, "'");
  const said = plain(summary);
  return alternatives.some((a) => said.includes(plain(a)));
}
