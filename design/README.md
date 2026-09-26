# Design assets

## Art (`design/art/`)

| File | Used for |
|---|---|
| `mascot.png` | The Notchman mascot everywhere: Home, History, Player (with "TL;DR" on its bar), mini player, Share sheet, Dynamic Island |
| `mascot-collar.png` | Sign-in and Account |
| `mascot-talk.png` | Onboarding |
| `app-icon.png` | App icon, the "Tap your notch" onboarding page, Safari extension icons |

After replacing any of these, run `python3 scripts/import_art.py`. It removes the dark backgrounds automatically and regenerates every asset. It needs Pillow and numpy.

## App logos (`design/logos/`, optional)

Logos are automatic. Web content gets the site's own icon, and apps get their App Store icon, matched by exact name.

Only add a file here to override one logo. Name it after the source as shown in Notchman, for example `ChatGPT.png`, then run `python3 scripts/import_logos.py`.

Before shipping, check each company's brand guidelines for using their logo to label content.
