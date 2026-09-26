# Design assets

Drop the real files here and run the scripts. The app picks them up automatically.

| File | Used for | Then run |
|---|---|---|
| `mascot.png` | The Notchman mascot everywhere (app, Share sheet, Dynamic Island). Transparent background; pixel art at its native size (it's scaled without smoothing). | `python3 scripts/generate_mascot.py` |
| `app-icon.png` | App icon, 1024×1024, no transparency | `python3 scripts/generate_mascot.py` |
| `logos/<Source name>.png` | Optional override for one source's logo, e.g. `ChatGPT.png`, `WhatsApp.pdf` | `python3 scripts/import_logos.py` |

**Logos are automatic.** For web content Notchman uses the site's own icon; for apps it uses the App Store icon, matched by exact app name. Only add a file here to override a logo that looks wrong, or for an app the App Store doesn't list.

Before shipping, check each company's brand guidelines for using their logo to label content.
