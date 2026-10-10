#!/usr/bin/env python3
"""App Store screenshots: each simulator screenshot (docs/screenshots, made by
the Screenshots workflow) on the app's sky with a short caption on top.

  python3 scripts/store_screenshots.py   # writes docs/store/01-….png … (1320×2868, 6.9" iPhone)

The order is the order on the App Store: the first three matter most.
"""
import os

from PIL import Image, ImageDraw, ImageFont

SIZE = (1320, 2868)
FONT = os.path.join(os.path.dirname(__file__), "..", "design", "store", "InterDisplay-Bold.woff2")
SOURCE = "docs/screenshots"
OUT = "docs/store"
NAVY = (11, 31, 68)

SHOTS = [
    ("player", "Hear the TL;DR,\nnot the wall of text"),
    ("onboardingTry", "Copy. Hold the Shiba.\nTap TL;DR."),
    ("home", "Messages, emails,\narticles, AI answers"),
    ("fullread", "Or hear every word,\nread aloud"),
    ("history", "Every listen, saved\non your iPhone"),
    ("paywall", "A natural voice,\nin your language"),
]


def sky(size):
    """The app's background: #7CC0F4 at the top to #EAF6FF at the bottom."""
    stops = [(0.0, (124, 192, 244)), (0.38, (185, 222, 249)), (1.0, (234, 246, 255))]
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / (size[1] - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                f = (t - t0) / (t1 - t0)
                draw.line([(0, y), (size[0], y)], fill=tuple(round(a + (b - a) * f) for a, b in zip(c0, c1)))
                break
    return image


def caption_font(text, width):
    """The largest size up to 112 px at which every line fits the width."""
    for size in range(112, 60, -2):
        font = ImageFont.truetype(FONT, size)
        if all(font.getlength(line) <= width for line in text.split("\n")):
            return font
    return ImageFont.truetype(FONT, 60)


def compose(name, caption):
    canvas = sky(SIZE)
    draw = ImageDraw.Draw(canvas)
    font = caption_font(caption, SIZE[0] - 160)
    draw.multiline_text((SIZE[0] / 2, 230), caption, font=font, fill=NAVY, anchor="ma", align="center", spacing=22)

    # The phone screen, scaled down, rising from the bottom edge.
    shot = Image.open(os.path.join(SOURCE, f"{name}.png")).convert("RGB")
    width = 1040
    height = round(shot.height * width / shot.width)
    shot = shot.resize((width, height), Image.LANCZOS)
    left, top, bezel, radius = (SIZE[0] - width) // 2, 640, 18, 96
    frame = Image.new("L", (width + 2 * bezel, height + 2 * bezel), 0)
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius=radius + bezel, fill=255)
    canvas.paste(Image.new("RGB", frame.size, NAVY), (left - bezel, top - bezel), frame)
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, height - 1], radius=radius, fill=255)
    canvas.paste(shot, (left, top), mask)
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".png"):
            os.remove(os.path.join(OUT, old))
    for index, (name, caption) in enumerate(SHOTS, 1):
        path = os.path.join(OUT, f"{index:02d}-{name}.png")
        compose(name, caption).save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main()
