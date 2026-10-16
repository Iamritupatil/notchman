#!/usr/bin/env python3
"""The App Store header (Product Page Information → Header): 3840×1646.

Same look as the screenshots (scripts/store_screenshots.py). It shows what
Notchman is about: it stays in the Dynamic Island and works over any other
app, without opening Notchman. The front iPhone is a group chat with
Notchman's Dynamic Island open over it (the real Live Activity, from the
onboarding capture); behind it, the TL;DR playing. Apple crops the sides on
smaller screens, so everything sits in the middle.

  python3 scripts/store_header.py      → docs/store/header.png
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import store_screenshots as s

W, H = 3840, 1646
BUBBLE = (233, 234, 238)
BLUE = (10, 132, 255)

CHAT = [
    ("Priya", "Hey! Quick update for Saturday. We're meeting at Cafe Mocha at 11:30, not 11, because "
              "Rohan's train gets in late. Bring ₹500 each for lunch; I've already paid the deposit. "
              "After lunch we'll walk to the lake if it doesn't rain, so bring shoes you can walk in."),
    ("Rohan", "Sorry all, train's late again. Also can someone check if the cafe has a table for six? "
              "And who's picking up the cake?"),
    (None, "tl;dr anyone?"),
]


def chat_screen():
    """A group chat in another app, with Notchman's Dynamic Island opened over it."""
    w, h = s.SIZE
    screen = Image.new("RGBA", s.SIZE, (255, 255, 255, 255))
    draw = ImageDraw.Draw(screen)
    # The chat's header.
    draw.rectangle([0, 0, w, 600], fill=(247, 247, 250))
    draw.line([(0, 600), (w, 600)], fill=(222, 222, 228), width=3)
    draw.text((w / 2, 540), "Weekend crew", font=s.font("Inter-SemiBold.ttf", 46), fill=(20, 20, 26), anchor="mm")
    draw.line([(80, 505), (50, 540), (80, 575)], fill=BLUE, width=9, joint="curve")

    text_font, name_font = s.font("Inter-Medium.ttf", 52), s.font("Inter-Medium.ttf", 38)
    y = 660
    for name, text in CHAT:
        mine = name is None
        lines = s.wrap(text, "Inter-Medium.ttf", 52, 820)
        width = max(text_font.getlength(line) for line in lines) + 84
        height = len(lines) * 68 + 56
        if not mine:
            draw.text((90, y), name, font=name_font, fill=(130, 132, 142))
            y += 56
        x0 = w - 60 - width if mine else 60
        draw.rounded_rectangle([x0, y, x0 + width, y + height], radius=52, fill=BLUE if mine else BUBBLE)
        for i, line in enumerate(lines):
            draw.text((x0 + 42, y + 28 + i * 68), line, font=text_font, fill=s.WHITE if mine else (20, 20, 26))
        y += height + 50
    # The typing bar.
    draw.rounded_rectangle([60, 2640, w - 60, 2760], radius=60, outline=(214, 214, 222), width=4)
    draw.text((120, 2700), "iMessage", font=text_font, fill=(170, 172, 182), anchor="lm")
    s.status_bar(screen)

    # Notchman's Dynamic Island, opened (the real Live Activity, cut from the onboarding capture).
    island = Image.open(os.path.join(s.SHOTS, "onboardingTry.png")).convert("RGB").crop((72, 1063, 1248, 1439))
    island = island.resize((1250, round(island.height * 1250 / island.width)), Image.LANCZOS)
    mask = Image.new("L", island.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, island.width - 1, island.height - 1], radius=150, fill=255)
    island = island.convert("RGBA")
    island.putalpha(mask)
    lifted, pad = s.shadowed(island, 30, (0, 20), 90)
    screen.alpha_composite(lifted, ((w - island.width) // 2 - pad, 34 - pad))
    # A tap on TL;DR.
    s.ripple(screen, (w / 2 - 70, 34 + 250), 40)
    return screen


def check(canvas, x, y, r):
    draw = ImageDraw.Draw(canvas)
    draw.ellipse([x - r, y - r, x + r, y + r], fill=s.WHITE)
    draw.line([(x - r * 0.42, y + r * 0.02), (x - r * 0.1, y + r * 0.34), (x + r * 0.45, y - r * 0.3)],
              fill=(31, 112, 230), width=round(r * 0.22), joint="curve")


def main():
    canvas = s.gradient((W, H), [(0, (31, 112, 230)), (0.55, (78, 148, 238)), (1, (160, 205, 250))])
    light = s.layer((W, H), s.WHITE)
    ImageDraw.Draw(light).ellipse([500, -500, 2100, 700], fill=(255, 255, 255, 50))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(220)))
    for x, y, size, rays in [(480, 250, 130, 4), (3200, 240, 90, 8), (640, 1380, 64, 8), (3170, 1340, 110, 4)]:
        s.sparkle(canvas, (x, y), size, angle=-72 if rays == 4 else 0, rays=rays)

    # The words.
    left = 700
    words = s.layer((W, H), s.WHITE)
    draw = ImageDraw.Draw(words)
    big = s.font("InterDisplay-ExtraBold.ttf", 165)
    for i, line in enumerate(["Lives in your", "Dynamic Island"]):
        draw.text((left, 360 + i * 180), line, font=big, fill=s.WHITE + (255,))
    rows = ["Works over any app", "No need to open Notchman", "Copy, tap TL;DR, listen"]
    row_font = s.font("Inter-SemiBold.ttf", 64)
    for i, text in enumerate(rows):
        draw.text((left + 100, 860 + i * 125), text, font=row_font, fill=s.WHITE + (255,), anchor="lm")
    lift = Image.new("RGBA", (W, H), (8, 30, 84, 0))
    lift.putalpha(words.getchannel("A").point(lambda a: a * 60 // 255))
    canvas.alpha_composite(lift.filter(ImageFilter.GaussianBlur(16)), (0, 8))
    canvas.alpha_composite(words)
    for i in range(len(rows)):
        check(canvas, left + 34, 860 + i * 125, 34)

    # The TL;DR playing behind; the chat with Notchman's Dynamic Island in front.
    back, pad = s.device(s.app_screen("shiba/player"), 450)
    canvas.alpha_composite(back, (2490 - pad, 300 - pad))
    width, x, y = 520, 1990, 190
    front, pad = s.device(chat_screen(), width)
    body_w = front.width - 2 * pad
    edge = (0.0135 + 0.029) * width
    s.peek(canvas, y, x + body_w * 0.8, 7, "listen1", lambda: canvas.alpha_composite(front, (x - pad, y - pad)), edge * 0.55)

    out = os.path.join(s.OUT, "header.png")
    canvas.convert("RGB").save(out, optimize=True)
    print(os.path.relpath(out, s.ROOT))


if __name__ == "__main__":
    main()
