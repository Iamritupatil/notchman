# Design assets

Drop the real files here and run the scripts. The app picks them up automatically.

| File | Used for | Then run |
|---|---|---|
| `mascot.png` | The Notchman mascot everywhere (app, Share sheet, Dynamic Island). Transparent background; pixel art at its native size (it's scaled without smoothing). | `python3 scripts/generate_mascot.py` |
| `app-icon.png` | App icon, 1024×1024, no transparency | `python3 scripts/generate_mascot.py` |
| `logos/chatgpt.png` | Source logo for ChatGPT | `python3 scripts/import_logos.py` |
| `logos/claude.png` | Claude | 〃 |
| `logos/gemini.png` | Gemini | 〃 |
| `logos/reddit.png` | Reddit | 〃 |
| `logos/mail.png` | Email | 〃 |
| `logos/safari.png` | Web pages | 〃 |
| `logos/messages.png` | Plain text / Messages | 〃 |

Logos can be `.png`, `.pdf` or `.svg`, square, ideally with a transparent background.
Until a logo exists, the tile shows a neutral symbol.

Before shipping, check each company's brand guidelines for using their logo to label content.
