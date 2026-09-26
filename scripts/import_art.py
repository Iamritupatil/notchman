#!/usr/bin/env python3
"""Builds the app's mascot, icon and extension assets from design/art/.

  design/art/mascot.png         main mascot (paws on the amber bar)
  design/art/mascot-collar.png  sign-in screen
  design/art/mascot-talk.png    onboarding
  design/art/app-icon.png       app icon, onboarding "tap your notch" art, Safari icons

Dark, flat backgrounds are removed automatically (flood fill from the edges),
so the art sits on any screen. Re-run after replacing any file:

  python3 scripts/import_art.py      (requires Pillow and numpy)
"""
import json
import shutil
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "design/art"
APP = ROOT / "Notchman/Resources/Assets.xcassets"
SHARE = ROOT / "Extensions/ShareExtension/Assets.xcassets"
WIDGET = ROOT / "Extensions/LiveActivityWidget/Assets.xcassets"
SAFARI = ROOT / "Extensions/SafariExtension/Resources/images"


def cutout(path, tolerance=14):
    """Makes the dark background connected to the image edges transparent."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    background = np.zeros((h, w), bool)
    queue = deque()
    for x in range(w):
        queue.extend([(0, x), (h - 1, x)])
    for y in range(h):
        queue.extend([(y, 0), (y, w - 1)])
    for y, x in queue:
        background[y, x] = True
    while queue:
        y, x = queue.popleft()
        color = rgb[y, x]
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and not background[ny, nx]:
                neighbor = rgb[ny, nx]
                if abs(neighbor - color).sum() < tolerance and neighbor.sum() < 200:
                    background[ny, nx] = True
                    queue.append((ny, nx))
    rgba = np.dstack([rgb, np.where(background, 0, 255)]).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA")
    return image.crop(image.getbbox())


def fit(image, width):
    if image.width <= width:
        return image
    return image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)


def ensure_catalog(catalog):
    catalog.mkdir(parents=True, exist_ok=True)
    contents = catalog / "Contents.json"
    if not contents.exists():
        contents.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))


def imageset(catalog, name, image):
    ensure_catalog(catalog)
    folder = catalog / f"{name}.imageset"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir()
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))


def main():
    mascot = cutout(ART / "mascot.png")
    imageset(APP, "Mascot", fit(mascot, 600))
    imageset(SHARE, "Mascot", fit(mascot, 300))
    imageset(WIDGET, "Mascot", fit(mascot, 120))
    imageset(APP, "MascotCollar", fit(cutout(ART / "mascot-collar.png"), 600))
    imageset(APP, "MascotTalk", fit(cutout(ART / "mascot-talk.png"), 600))

    icon = Image.open(ART / "app-icon.png").convert("RGB").resize((1024, 1024), Image.LANCZOS)
    imageset(APP, "OnboardingNotch", icon.resize((800, 800), Image.LANCZOS))

    appicon = APP / "AppIcon.appiconset"
    for old in appicon.glob("*.png"):
        old.unlink()
    icon.save(appicon / "AppIcon-1024.png")
    (appicon / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))

    for size in (48, 64, 96, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(SAFARI / f"icon-{size}.png")
    small = fit(mascot, 256)
    for size in (16, 19, 32, 38, 48, 72):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        glyph = small.resize((size, round(size * small.height / small.width)), Image.LANCZOS)
        canvas.alpha_composite(glyph, (0, (size - glyph.height) // 2))
        canvas.save(SAFARI / f"toolbar-icon-{size}.png")
    print("Imported mascot, collar, talk, onboarding art, app icon and Safari icons.")


if __name__ == "__main__":
    main()
