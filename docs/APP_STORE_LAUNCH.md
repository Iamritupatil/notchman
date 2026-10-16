# Notchman on the App Store: launch kit

Everything to submit Notchman for iPhone and help it get found. Checked against
App Store Connect on October 15, 2026 (Actions → App Store → readiness).

**You** = only you can do it (your Apple account). **Done** = already set.
**Run** = a GitHub Action does it (Actions → App Store → Run workflow → pick the action).

## 1. Submission checklist

### Agreements and money (App Store Connect → Business)
- [ ] **You:** Paid Apps Agreement accepted (needed for any in-app purchase).
- [ ] **You:** Tax forms and bank account filled in, status "Active".
- [ ] **You:** Apply to the **App Store Small Business Program**: 15% commission instead of 30%.

### App information
- [x] **Done:** name "Notchman: Summarize & Listen", categories Productivity / Utilities.
- [x] **Done:** age rating 4+, content rights declared, privacy policy URL.
- [x] **Done:** subtitle "Text to Speech & AI Summary" and the keywords (section 3) applied on October 15.

### App Privacy (App Store Connect → App Privacy; not possible through the API)
- [ ] **You:** answer exactly like this. "Used for tracking" is **No** for all of them. Only the account details (email, name, user ID) are linked to the user.

| Data type | Collected? | Purpose |
| --- | --- | --- |
| User Content → Other User Content (text you TL;DR, sent to Groq and ElevenLabs) | Yes | App Functionality |
| Identifiers → Device ID (the random install ID) | Yes | App Functionality |
| Usage Data → Product Interaction (anonymous app statistics) | Yes | Analytics |
| Purchases → Purchase History (to unlock Pro) | Yes | App Functionality |
| Contact Info → Email Address (Sign in with Apple, optional) | Yes, **linked to the user** | App Functionality, Customer Support |
| Contact Info → Name (if they share it) | Yes, **linked to the user** | App Functionality |
| Identifiers → User ID (the Apple account ID for Notchman) | Yes, **linked to the user** | App Functionality |
| Location, Health, Contacts, Browsing History, Diagnostics, other Contact Info | No | – |

### Version 1.0
- [x] **Done:** description, promotional text, support and marketing URLs, copyright.
- [x] **Done:** updated description and promotional text applied (design/store/listing.json).
- [x] **Done:** the 4 new screenshots from docs/store/main are uploaded (October 16). Header: docs/store/header.png (upload it by hand).
- [ ] **You:** App Review → **phone number** (Apple won't save the review contact without it; that's why it shows MISSING).
- [x] **Done:** build 56 (head-only Shiba, rating prompt) is attached to version 1.0. After a new TestFlight build, run `listing` again to attach it.
- [ ] **You:** version 1.0 → **In-App Purchases and Subscriptions** → add **Pro** and **Pro+**. Both must say "Ready to Submit". A first subscription can only be reviewed together with an app version.
- [ ] **You:** Release: "Manually release this version" is safer for a launch day you choose.

### What App Review checks (and where Notchman stands)
| Rule | What it asks | Notchman |
| --- | --- | --- |
| 2.1 App completeness | Reviewer can use every feature | No account needed; review notes explain the Dynamic Island flow. Done |
| 5.1.2(i) Third-party AI | Name the AI services and get explicit permission before sending data | Agreement screen names Groq and ElevenLabs, the box must be ticked. Done |
| 3.1.2 Subscriptions | Show what you get for the price, length, renewal, Restore, Terms and Privacy | The paywall has all of these. Done |
| 2.3.7 Metadata | No competitor names, prices or keyword stuffing in name, subtitle, screenshots | New keywords and screenshots follow it (no prices, no other apps' names). Done |
| 2.3.10 Other platforms | No Android or Windows imagery in iPhone metadata | Screenshots show only iPhone. Done |
| 2.5.4 Background | Background audio only for playing audio | Only used for the voice. Done |
| 5.1.1 Privacy | Privacy policy, and App Privacy answers that match the app | Policy live; you answer App Privacy (above). |
| Clipboard | Read only when the user acts | Only on TL;DR / Read. Done |
| Export compliance | Encryption question | ITSAppUsesNonExemptEncryption = NO (HTTPS only). Done |
| Privacy manifests | Required-reason APIs declared | App and all 3 extensions have PrivacyInfo.xcprivacy. Done |

## 2. Screenshots

`python3 scripts/store_screenshots.py` makes them from the simulator screens
(Actions → Screenshots). Size: 1320 × 2868 (6.9-inch iPhone). Apple scales it
for smaller iPhones. iPad isn't needed: Notchman is iPhone-only.

Every page (docs/store/<page>) has four, in this style: an iPhone on a blue
sky, the Shiba's head peeking over it.
1. The hero: the Shiba over a big Dynamic Island, "Tap your Dynamic Island…"
2. The TL;DR playing that page's text, under a headline like "Too long? Hear the TL;DR"
3. Its key points, the iPhone rising out of clouds
4. Home, history or "finding what matters" for that audience

Why they look like this: Apple reads the text on screenshots for search (an
ASO finding since mid-2025, not an official Apple statement), so captions use
the words people type ("summarize", "text to speech", "key points") in bold,
high-contrast type. The real UI is shown, and the Shiba is just its head.

## 3. App Store search (ASO)

| Field | Text | Chars |
| --- | --- | --- |
| Name (strongest) | Notchman: Summarize & Listen | 28/30 |
| Subtitle (strong) | Text to Speech & AI Summary | 27/30 |
| Keywords (hidden) | tldr,summarizer,reader,read,aloud,voice,tts,audio,article,email,adhd,dyslexia,study,gist,brief,news | 99/100 |

Rules followed: no word repeated across name, subtitle and keywords (Apple
combines them, e.g. "summarize" + "text to speech" + "reader"); commas, no
spaces; no competitor names like Speechify (2.3.7).

**Next steps for ranking**
- **Ratings:** the app now asks for a rating after the 3rd, 10th and 30th listen that plays to the end. Ratings count and recency are a big ranking signal.
- **Localizations:** add English (UK) and Spanish (Mexico). Each one gets its own 100-character keyword field, and ASO tools report that the US store also reads the Spanish (Mexico) keywords.
- **In-App Events:** e.g. "Exam season: listen to your readings". Events show up in search and on the product page.
- **Featuring:** App Store Connect → Featuring → **Nominate** the launch 2–3 weeks ahead. Apple's editors pick from nominations, and a feature can bring a big wave of downloads.
- **Check every 2 weeks:** search the keywords on an iPhone and note the rank. Swap out words that don't rank after a month.

## 4. Custom product pages

You can make up to 70 pages, each with its own screenshots and promotional
text. Since July 2025 a page can also show in **search** for keywords you
give it (keywords must already be in the app's keyword field). Each page has
its own link: use it in matching posts, ads and bios. Screenshots are in
docs/store/<page>: its own first three, then main 04–07.

**Created on October 16** (Actions → App Store → `custom-pages`), each with its promotional text and
four screenshots. Search keywords can only be added once version 1.0 is live: run `custom-pages`
again after launch, then submit the pages for review in App Store Connect.

| Page | Link |
| --- | --- |
| study | https://apps.apple.com/us/app/notchman/id6816657500?ppid=4fc0c133-db8f-4407-a120-3c723d00c59a |
| work | https://apps.apple.com/us/app/notchman/id6816657500?ppid=52ecc3b8-33ac-4c43-bd0b-4c9c1bb8eeb1 |
| focus | https://apps.apple.com/us/app/notchman/id6816657500?ppid=e27364b6-7f03-4b03-b9e2-dc31153be3f9 |
| ai | https://apps.apple.com/us/app/notchman/id6816657500?ppid=9b3d9cfa-2eb3-4215-8ca2-7337f45810b7 |
| shiba | https://apps.apple.com/us/app/notchman/id6816657500?ppid=97dc0cf9-924d-42e5-99a0-b2f5e3423652 |

| Page | Who | Promotional text | Search keywords | Use its link in |
| --- | --- | --- | --- | --- |
| study | Students, exam prep | Turn long readings and research papers into key points you can hear on the way to class. | study, summarizer, read aloud | Student Reels, college groups |
| work | Busy professionals | Long emails, chats and docs, summarized in seconds. Every name, date and number kept. | email, gist, brief | LinkedIn posts |
| focus | People who find walls of text hard | Too much to read? Notchman reads it to you: a short TL;DR, or every word at your speed. | adhd, dyslexia, reader, aloud | Accessibility communities |
| ai | Heavy AI-chat users | Long AI answers? Copy, hold the Shiba, and hear just the key points. | summarizer, tldr | AI tips Reels |
| shiba | Instagram followers | Meet the Shiba that reads for you. Copy anything, hear what matters. | (none: link only) | **Instagram bio and Reels** (most of your visitors) |

Don't promise medical help on the focus page ("helps with ADHD"); describe
what it does ("reads it to you") instead.

## 5. What growing consumer apps do (and what fits Notchman)

- **A mascot people love.** Finch grew mostly by word of mouth with a pet you look after (4.9 stars from about 663,000 ratings, an Editors' Choice, and seasonal events). Notchman's Shiba is that hook: give it a personality on Reels.
- **Many creators, small ones.** The playbook in 2026 is 15–30 small creators (1K–100K followers) posting real use, then boosting the best posts as ads. For Notchman: students showing "my 10-page reading in 2 minutes", professionals showing a long email turned into a TL;DR.
- **Demo-first videos.** The hook is the result in the first 2 seconds: the Shiba in the Dynamic Island, tap, voice starts. Your Instagram Reels already bring most of your website visitors.
- **One page per audience.** Each kind of video links to its custom product page, so the screenshots match what the viewer just saw.
- **Ask at the happy moment.** Rate prompts after a successful listen (done), and a share prompt after a good TL;DR (next).

Sources: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[TechCrunch on the AI data rule](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai),
[RespectASO: 70 custom product pages](https://respectaso.com/blog/custom-product-pages-app-store-guide-2026/),
[Yodel: custom product pages in search](https://yodelmobile.com/apple-custom-product-pages-now-target-keywords/),
[AppFollow: ranking factors](https://appfollow.io/blog/aso-ranking-factors),
[Adalo: screenshot sizes](https://studio.adalo.com/blog/app-store-screenshot-sizes-2026),
[Finch on the App Store](https://apps.apple.com/app/id1528595748),
[FoxData on Finch](https://foxdata.com/en/blogs/finch-as-app-store-editors-choice-a-self-care-companion/),
[Superscale: TikTok UGC for apps](https://superscale.ai/learn/tiktok-ugc-strategy-how-to-go-viral-for-your-app-in-2025/),
[Stackmatix: UGC ads](https://www.stackmatix.com/blog/tiktok-ugc-ads-strategy).
