// Test texts for the TL;DR evaluation (scripts/eval-tldr.mjs). Each case lists
// what a listener must know afterwards (`mustCover`, as regular expressions
// matched case-insensitively) and things that would be wrong to say (`mustNot`).

export const CASES = [
  {
    name: "1. Long ChatGPT technical answer",
    text: `Great question! Choosing between PostgreSQL and MongoDB for your SaaS really depends on your data and how it will grow, so let me walk you through it in detail.

**1. Data model.** PostgreSQL is relational: data lives in tables with a fixed schema, and you connect tables with joins. That's ideal when your data is highly connected, like users, teams, invoices and permissions, because the database itself enforces the relationships. MongoDB stores JSON-like documents, so each record can have a different shape. That's convenient when your data varies a lot, like product catalogs where every product has different attributes.

**2. Transactions and consistency.** PostgreSQL has had full ACID transactions for decades. ACID basically means that a group of changes either all happen or none do, even if the server crashes halfway. For billing and payments, that matters a lot. MongoDB added multi-document transactions in version 4.0, but they are slower and come with limits, for example a default 60-second transaction lifetime.

**3. Scaling.** MongoDB was designed for horizontal scaling through sharding, which means splitting data across many machines. PostgreSQL usually scales vertically on one bigger machine, plus read replicas. In practice, a single well-tuned PostgreSQL server comfortably handles most SaaS products up to tens of millions of rows, and extensions like Citus can shard it if you ever need that.

**4. Querying and reporting.** If you'll need complex reports (revenue per plan per month, churn by cohort), SQL in PostgreSQL is far easier. MongoDB's aggregation pipeline can do it, but queries get long and hard to maintain.

**5. Flexibility.** PostgreSQL has a JSONB column type, so you can still store flexible documents inside a relational database and even index them.

**My recommendation:** for a typical B2B SaaS with users, teams and billing, start with PostgreSQL. Use JSONB columns for the few parts that need flexible data. Choose MongoDB only if most of your data is truly unstructured or you already know you'll need to shard across many servers early on. One caveat: whichever you pick, set up automated backups and test restoring them, because that's the mistake that hurts teams most.

I hope this helps! Let me know if you want a sample schema.`,
    mustCover: [/postgres/i, /mongo/i, /(acid|all happen or none|all or nothing)/i, /(join|relational|relationship)/i, /shard/i, /jsonb/i, /(report|sql)/i, /(backup|restor)/i, /(4\.0|60)/],
    mustNot: [/I hope this helps/i, /sample schema/i],
  },
  {
    name: "2. Long LinkedIn post",
    text: `I almost quit my startup 18 months ago. 💔

Here's what happened, and what I learned. 🧵

We had raised $1.2M, hired 9 people, and built for 14 months. Our launch got 3,000 signups in a week. Everyone celebrated.

Then the numbers came in. Day-30 retention: 6%. Out of 3,000 people, fewer than 200 were still using the product a month later.

I spent two weeks in denial. Then I did the only thing that worked: I called 60 churned users, one by one.

Three lessons changed everything:

1️⃣ Signups are vanity. Retention is reality. We had optimized our onboarding for signups, not for the first moment of value. When we cut onboarding from 9 steps to 3 and got people to their first report in under 2 minutes, day-30 retention went from 6% to 31% in one quarter.

2️⃣ Your best users tell you what to build. 40 of the 60 people I called wanted the same thing: a Slack integration. We had it on the roadmap for "next year." We shipped it in 5 weeks.

3️⃣ Cut scope ruthlessly. We killed 4 features that fewer than 2% of users touched. Fewer features meant fewer bugs and a faster team.

Today we're at $85K MRR, growing 12% month over month, with the same 9 people.

If you're staring at bad retention numbers right now: it's not the end. It's data.

Agree? ♻️ Repost to help a founder who needs this. Follow me for more startup lessons.`,
    mustCover: [/\b(6|six) ?(%|per ?cent)/i, /\b(31|thirty[- ]one) ?(%|per ?cent)/i, /(60|sixty)/i, /slack/i, /(9|nine) steps?.*(3|three)|(3|three) steps/i, /(4|four) features/i, /85/i, /\b(12|twelve) ?(%|per ?cent)/i, /retention/i],
    mustNot: [/repost/i, /follow me/i],
  },
  {
    name: "3. Educational explanation",
    text: `How does compound interest work, and why does starting early matter so much?

Simple interest is calculated only on the money you originally put in, called the principal. If you invest 10,000 rupees at 10% simple interest, you earn 1,000 rupees every year, no matter how long you wait.

Compound interest is different: the interest you earn is added to your balance, and next year you earn interest on that interest too. With the same 10,000 rupees at 10% compounded yearly, you'd have 11,000 after one year, 12,100 after two years, and about 25,937 after ten years, compared with 20,000 under simple interest.

The key variable is time. Because growth builds on itself, the later years contribute far more than the early ones. A useful shortcut is the Rule of 72: divide 72 by the annual interest rate to estimate how many years it takes to double your money. At 8%, money doubles roughly every 9 years.

That's why starting early matters. Suppose Asha invests 5,000 rupees a month from age 25 to 35 and then stops, while Ravi invests the same amount from 35 to 60. Assuming 10% annual returns, Asha can end up with a similar or larger amount at 60 than Ravi, despite investing for 10 years instead of 25, because her money had more time to compound.

Two caveats: real investments don't return a fixed rate every year, and inflation reduces what the final amount can buy. Compounding also works against you with debt, like credit cards, where unpaid interest gets charged interest.`,
    mustCover: [/simple interest/i, /interest on (the )?interest|interest.*added/i, /(12,?100|25,?937)/, /(rule of 72|rule of seventy[- ]two|divide 72|72 divided)/i, /(9|nine) years/i, /asha/i, /ravi/i, /inflation/i, /(debt|credit card)/i],
    mustNot: [],
  },
  {
    name: "4. Message with dates, numbers and action items",
    text: `Hi team! Quick update after today's call with Acme. They've approved the redesign, but the launch is moving from 3 March to 17 March because their legal team needs to review the new privacy page. Budget stays at ₹4.5 lakh. Priya, please send the final mockups to their marketing lead by Friday 28 February, 5pm. Arjun, the payment page bug (double charge on retry) must be fixed before 10 March or they won't sign off. I'll book the review call for 12 March. Thanks all!`,
    mustCover: [/acme/i, /(17(th)? (of )?march|march 17|seventeenth)/i, /legal/i, /(4\.5 lakh|450,?000|four (point|and a half) ?(five )?lakh)/i, /priya/i, /(28(th)? (of )?february|february 28|friday)/i, /\b(5|five) ?(pm|p\.m\.|in the evening|o'?clock)/i, /arjun/i, /(double charge|charged twice)/i, /(10(th)? (of )?march|march 10|tenth of march)/i, /(12(th)? (of )?march|march 12|twelfth of march)/i],
    mustNot: [],
  },
  {
    name: "5. Argument with opposing points",
    text: `Should our company switch to a four-day work week? The leadership team is split, and here are both sides as they were presented in yesterday's meeting.

Those in favour, led by Meera from HR, point to the 2022 UK pilot, where 56 of 61 companies kept the four-day week after six months and reported lower burnout. They argue it would help us hire, since three of our last five candidates turned down offers for more flexible employers, and that our own survey found 78% of staff would prefer it.

Those against, led by Daniel from Sales, argue that our customers expect support five days a week, so we would need staggered schedules, which adds complexity. He also notes that the pilot companies were mostly small office-based firms, so the results may not apply to a 400-person company with a customer support team. Finance estimates that covering support coverage could cost an extra 6% in payroll.

A compromise was proposed: a six-month trial in engineering and design only, with support staying on five days, measured on output, retention and customer satisfaction. No decision was made; the CEO will decide by the end of the quarter.`,
    mustCover: [/meera/i, /daniel/i, /56/, /61/, /\b(78|seventy[- ]eight) ?(%|per ?cent)/i, /(three|3) of (our|the) last (five|5)/i, /(400|small)/i, /\b(6|six) ?(%|per ?cent)/i, /(six|6)[- ]month/i, /(engineering|design)/i, /no decision|not (yet )?decided|hasn'?t decided/i, /end of the quarter/i],
    mustNot: [/(will|is going to) switch to a four-day/i],
  },
  {
    name: "6. Very repetitive long post",
    text: `Consistency is everything. I mean it. Consistency is everything in business, in fitness, in life.

When I started writing online, nobody read my posts. But I stayed consistent. I posted every single day. Every day. No matter what.

Consistency beats talent. Consistency beats motivation. Consistency beats luck. If you remember one thing from this post, remember this: consistency is everything.

Some days I didn't feel like writing. I wrote anyway. Because consistency. Some days nobody liked my posts. I posted anyway. Because consistency.

After 365 days of posting every day, I had 50,000 followers. Not because I was the best writer. Because I was consistent.

Let me say it again, because it matters: consistency is everything. Show up every day. Even when it's hard. Especially when it's hard. Consistency compounds. Small actions, repeated daily, become big results.

So here's my challenge to you: post every day for the next 30 days. Be consistent. That's it. That's the post. Consistency is everything.`,
    mustCover: [/consisten/i, /365|a year|every day for a year/i, /50,?000/i, /(30|thirty) days/i],
    mustNot: [],
    maxRatio: 0.35,
  },
  {
    name: "7. Dense information-heavy post",
    text: `Q3 results summary for the board. Revenue was ₹38.2 crore, up 22% year over year but 4% below our ₹39.8 crore target, mainly because two enterprise deals (Zenith and Corva, together ₹2.1 crore) slipped into Q4; both have signed letters of intent. Gross margin improved from 61% to 66% after we moved inference to our own GPUs, which cut cloud costs by ₹1.4 crore per quarter. Net revenue retention was 118%, but logo churn rose from 2.1% to 3.4%, concentrated in customers under ₹5 lakh ARR, most citing price after the June increase. Cash at quarter end was ₹61 crore, giving 26 months of runway at the current burn of ₹2.35 crore per month. Headcount went from 212 to 231; we are pausing non-engineering hiring until Q4 revenue is confirmed. Risks: the new data-protection rules effective 1 April may require moving EU customer data to an EU region, estimated at ₹80 lakh one-time. Board asks: approve a ₹3 crore budget for the EU region and a 15% discount programme for small customers to reduce churn.`,
    mustCover: [/38\.2/, /\b(22|twenty[- ]two) ?(%|per ?cent)/i, /39\.8|4 ?(%|percent) (below|short|under)/i, /(zenith|corva)/i, /2\.1 crore/i, /\b66 ?(%|per ?cent)/i, /\b118 ?(%|per ?cent)/i, /3\.4 ?(%|per ?cent)/i, /61 crore/i, /26 months/i, /231/, /1 april/i, /80 lakh/i, /3 crore/i, /\b(15|fifteen) ?(%|per ?cent)/i],
    mustNot: [],
  },
];
