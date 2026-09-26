#!/usr/bin/env python3
"""Generates placeholder Notchman icons: a black Dynamic Island-shaped pill
wearing tiny coral headphones. Replace with final branding when ready.

Usage: python3 scripts/generate_icons.py   (requires Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
CORAL = (255, 91, 58, 255)
SS = 4  # supersampling for smooth edges


def mark(draw, cx, cy, w, fg_band, pill=(0, 0, 0, 255), eye=(255, 255, 255, 255)):
    """Draws the character centered at (cx, cy) with pill width w."""
    h = w * 0.36
    band_w = w * 0.9
    lw = max(2, int(w * 0.05))
    # Headband: upper half of an ellipse spanning the ear cups.
    top = cy - h * 1.55
    draw.arc([cx - band_w / 2, top, cx + band_w / 2, top + h * 2.4], 180, 360, fill=fg_band, width=lw)
    # Ear cups.
    cup_w, cup_h = w * 0.13, w * 0.26
    for sx in (-1, 1):
        x = cx + sx * band_w / 2
        draw.rounded_rectangle([x - cup_w / 2, cy - cup_h / 2, x + cup_w / 2, cy + cup_h / 2],
                               radius=cup_w * 0.4, fill=CORAL)
    # The notch.
    pw = w * 0.86
    draw.rounded_rectangle([cx - pw / 2, cy - h / 2, cx + pw / 2, cy + h / 2], radius=h / 2, fill=pill)
    # Eyes.
    r = w * 0.03
    for sx in (-1, 1):
        ex = cx + sx * w * 0.11
        draw.ellipse([ex - r, cy - r, ex + r, cy + r], fill=eye)


def icon(size, background, band, path, transparent=False):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0) if transparent else background)
    d = ImageDraw.Draw(img)
    mark(d, s / 2, s * 0.56, s * 0.68, band,
         pill=(0, 0, 0, 255) if background[0] > 128 or transparent else (18, 18, 18, 255))
    img = img.resize((size, size), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def main():
    app = ROOT / "Notchman/Resources/Assets.xcassets/AppIcon.appiconset"
    icon(1024, (255, 255, 255, 255), (0, 0, 0, 255), app / "AppIcon-1024.png")
    # Dark icon: pill gets a subtle outline via a lighter background.
    icon(1024, (38, 38, 40, 255), (235, 235, 235, 255), app / "AppIcon-1024-dark.png")

    safari = ROOT / "Extensions/SafariExtension/Resources/images"
    for size in (48, 64, 96, 128, 256, 512):
        icon(size, (255, 255, 255, 255), (0, 0, 0, 255), safari / f"icon-{size}.png")
    for size in (16, 19, 32, 38, 48, 72):
        icon(size, (0, 0, 0, 0), (0, 0, 0, 255), safari / f"toolbar-icon-{size}.png", transparent=True)


if __name__ == "__main__":
    main()
