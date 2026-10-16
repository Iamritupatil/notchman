#!/usr/bin/env python3
"""The App Store header (Product Page Information → Header): 3840×1646.

Same look as the screenshots (scripts/store_screenshots.py): blue sky,
sparkles, three iPhones (front to back: the hero, the player, key points) with the Shiba peeking. Apple crops the header's
sides on smaller screens, so everything sits in the middle.

  python3 scripts/store_header.py      → docs/store/header.png
"""
import os

from PIL import Image, ImageDraw, ImageFilter

import store_screenshots as s

W, H = 3840, 1646


def main():
    canvas = s.gradient((W, H), [(0, (31, 112, 230)), (0.55, (78, 148, 238)), (1, (160, 205, 250))])
    light = s.layer((W, H), s.WHITE)
    ImageDraw.Draw(light).ellipse([600, -500, 2200, 700], fill=(255, 255, 255, 50))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(220)))
    for x, y, size, rays in [(640, 230, 150, 4), (3500, 250, 90, 8), (820, 1360, 70, 8), (3480, 1330, 110, 4)]:
        s.sparkle(canvas, (x, y), size, angle=-72 if rays == 4 else 0, rays=rays)

    # The words, left of the middle.
    words = s.layer((W, H), s.WHITE)
    draw = ImageDraw.Draw(words)
    big = s.font("InterDisplay-ExtraBold.ttf", 150)
    for i, line in enumerate(["Copy anything.", "Hear what", "matters."]):
        draw.text((860, 470 + i * 160), line, font=big, fill=s.WHITE + (255,))
    draw.text((864, 980), "AI summary and text to speech,", font=s.font("Inter-Medium.ttf", 56), fill=(255, 255, 255, 236))
    draw.text((864, 1050), "from your Dynamic Island", font=s.font("Inter-Medium.ttf", 56), fill=(255, 255, 255, 236))
    lift = Image.new("RGBA", (W, H), (8, 30, 84, 0))
    lift.putalpha(words.getchannel("A").point(lambda a: a * 60 // 255))
    canvas.alpha_composite(lift.filter(ImageFilter.GaussianBlur(16)), (0, 8))
    canvas.alpha_composite(words)

    # Three iPhones right of the middle; the front one shows the hero.
    phones = [
        (s.app_screen("work/keyPoints"), 400, 2980, 380),
        (s.app_screen("shiba/player"), 440, 2630, 300),
        (s.hero_screen("Tap your\nDynamic Island.\nStart listening.",
                       "Notchman finds your long message, sums it up, and reads it out loud.", "listen1"), 500, 2150, 200),
    ]
    for screen, width, x, y in phones[:2]:
        phone, pad = s.device(screen, width)
        canvas.alpha_composite(phone, (x - pad, y - pad))
    screen, width, x, y = phones[2]
    phone, pad = s.device(screen, width)
    body_w = phone.width - 2 * pad
    edge = (0.0135 + 0.029) * width
    s.peek(canvas, y, x + body_w * 0.76, 7, "happy", lambda: canvas.alpha_composite(phone, (x - pad, y - pad)), edge * 0.55)

    out = os.path.join(s.OUT, "header.png")
    canvas.convert("RGB").save(out, optimize=True)
    print(os.path.relpath(out, s.ROOT))


if __name__ == "__main__":
    main()
