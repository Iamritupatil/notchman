#!/usr/bin/env python3
"""Product Hunt gallery images (1270×760) and thumbnail (240×240), in the
same blue-sky look as the App Store screenshots (scripts/store_screenshots.py).

The desktop pieces are the real app's UI, captured by the desktop app's test
harness (desktop/test/e2e/out): the player pill, the Shiba's menu, Settings and
Pick on screen. The iPhone is the App Store hero screen.

  python3 scripts/producthunt_images.py      → docs/producthunt/*.png
"""
import os

from PIL import Image, ImageDraw, ImageFilter

import store_screenshots as s

W, H = 1270, 760
OUT = os.path.join(s.ROOT, "docs/producthunt")
UI = os.path.join(s.ROOT, "desktop/test/e2e/out")
INK = (22, 26, 36)

CHAT = [
    ("you", "Should we launch the beta on Friday, or wait for the new onboarding next month?"),
    ("ai", "Launching on Friday is reasonable if the core flow works, because early feedback is worth more than "
           "polish. The risk is that the current onboarding loses about a third of new users before they reach "
           "their first result, so you would be measuring the onboarding problem rather than the product."),
    ("ai", "A middle path is to launch on Friday to a small group of 50 users you can talk to directly, fix the two "
           "biggest drop-off points over the next two weeks, and open the beta widely once day-7 retention is above "
           "30 percent. Whatever you choose, set up basic analytics before launch."),
]
EMAIL = ("Q3 launch plan", "Priya Shah", [
    "Hi team, a few updates before Thursday's all-hands. The launch moves from October 14 to October 28, because "
    "the payments review needs another week and we want the new onboarding in the first release.",
    "The budget goes up 12% to $48,000 to cover the extra testing. Priya owns the beta; feedback is due Friday. "
    "Export and dark mode are cut from this release and move to November.",
    "We'll walk through the plan at the all-hands on Thursday at 3 pm. Bring questions, and please read the "
    "attached timeline beforehand so we can keep the meeting short.",
])


def sky():
    canvas = s.gradient((W, H), [(0, (31, 112, 230)), (0.6, (88, 156, 240)), (1, (180, 216, 252))])
    light = s.layer((W, H), s.WHITE)
    ImageDraw.Draw(light).ellipse([-200, -260, 700, 420], fill=(255, 255, 255, 50))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(120)))
    return canvas


def title(canvas, text, sub, x=60, y=58, size=54, width=520):
    words = s.layer((W, H), s.WHITE)
    draw = ImageDraw.Draw(words)
    big = s.font("InterDisplay-ExtraBold.ttf", size)
    lines = text.split("\n")
    for i, line in enumerate(lines):
        draw.text((x, y + i * round(size * 1.1)), line, font=big, fill=s.WHITE + (255,))
    yy = y + len(lines) * round(size * 1.1) + 14
    for i, line in enumerate(s.wrap(sub, "Inter-Medium.ttf", 23, width)):
        draw.text((x, yy + i * 32), line, font=s.font("Inter-Medium.ttf", 23), fill=(255, 255, 255, 235))
    lift = Image.new("RGBA", (W, H), (8, 30, 84, 0))
    lift.putalpha(words.getchannel("A").point(lambda a: a * 60 // 255))
    canvas.alpha_composite(lift.filter(ImageFilter.GaussianBlur(10)), (0, 4))
    canvas.alpha_composite(words)


def window(size, kind, heading):
    """A desktop window: macOS (traffic lights) or Windows 11 (caption buttons)."""
    w, h = size
    win = s.layer(size)
    draw = ImageDraw.Draw(win)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=14 if kind == "mac" else 8, fill=(255, 255, 255, 255),
                           outline=(205, 210, 220, 255))
    bar = 40
    draw.rounded_rectangle([0, 0, w - 1, bar + 14], radius=14 if kind == "mac" else 8, fill=(240, 242, 246, 255))
    draw.rectangle([0, bar, w - 1, bar + 14], fill=(255, 255, 255, 255))
    draw.line([(0, bar), (w, bar)], fill=(222, 225, 232), width=1)
    f = s.font("Inter-SemiBold.ttf", 14)
    if kind == "mac":
        for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
            draw.ellipse([16 + i * 20, 14, 28 + i * 20, 26], fill=c)
        draw.text((w / 2, bar / 2), heading, font=f, fill=(70, 74, 84), anchor="mm")
    else:
        draw.text((16, bar / 2), heading, font=f, fill=(40, 44, 54), anchor="lm")
        c, y = (60, 64, 74), bar / 2
        x = w - 22 - 92
        draw.line([(x - 5, y), (x + 5, y)], fill=c, width=1)
        x = w - 22 - 46
        draw.rectangle([x - 5, y - 5, x + 5, y + 5], outline=c, width=1)
        x = w - 22
        draw.line([(x - 5, y - 5), (x + 5, y + 5)], fill=c, width=1)
        draw.line([(x - 5, y + 5), (x + 5, y - 5)], fill=c, width=1)
    return win, bar


def chat_window(size, kind):
    win, top = window(size, kind, "Chat")
    draw = ImageDraw.Draw(win)
    w, h = size
    draw.rectangle([0, top + 1, 170, h - 2], fill=(246, 247, 250))
    for i, t in enumerate(["New chat", "Pricing ideas", "Launch plan", "Trip to Japan"]):
        draw.text((20, top + 24 + i * 30), t, font=s.font("Inter-Medium.ttf", 14), fill=(90, 96, 110))
    f = s.font("Inter-Medium.ttf", 15)
    y = top + 24
    for who, text in CHAT:
        if who == "you":
            lines = s.wrap(text, "Inter-Medium.ttf", 15, 300)
            bw = max(f.getlength(l) for l in lines) + 28
            draw.rounded_rectangle([w - 30 - bw, y, w - 30, y + len(lines) * 22 + 18], radius=16, fill=(236, 239, 245))
            for i, l in enumerate(lines):
                draw.text((w - 16 - bw, y + 9 + i * 22), l, font=f, fill=INK)
            y += len(lines) * 22 + 34
        else:
            for l in s.wrap(text, "Inter-Medium.ttf", 15, w - 250):
                draw.text((200, y), l, font=f, fill=INK)
                y += 23
            y += 14
    return win


def email_window(size, kind):
    subject, sender, paragraphs = EMAIL
    win, top = window(size, kind, "Mail")
    draw = ImageDraw.Draw(win)
    w, h = size
    draw.text((30, top + 24), subject, font=s.font("InterDisplay-Bold.ttf", 24), fill=INK)
    draw.ellipse([30, top + 66, 66, top + 102], fill=(124, 92, 220))
    draw.text((48, top + 84), "P", font=s.font("Inter-SemiBold.ttf", 16), fill=s.WHITE, anchor="mm")
    draw.text((78, top + 70), sender, font=s.font("Inter-SemiBold.ttf", 15), fill=INK)
    draw.text((78, top + 90), "to Team", font=s.font("Inter-Medium.ttf", 13), fill=(120, 126, 140))
    y = top + 124
    for p in paragraphs:
        for l in s.wrap(p, "Inter-Medium.ttf", 15, w - 70):
            draw.text((30, y), l, font=s.font("Inter-Medium.ttf", 15), fill=INK)
            y += 23
        y += 12
    return win


def place(canvas, image, x, y, blur=22, opacity=90):
    lifted, pad = s.shadowed(image, blur, (0, blur // 2), opacity)
    canvas.alpha_composite(lifted, (x - pad, y - pad))


def pill():
    return Image.open(os.path.join(UI, "2-playing.png")).convert("RGBA")


def shiba_menu(scale=3):
    """The Shiba's menu (real capture) with the floating Shiba's head beside it."""
    menu = Image.open(os.path.join(UI, "8-buddy-menu.png")).convert("RGBA").crop((0, 0, 210, 140))
    out = s.layer((menu.width + 20 * scale + 30, menu.height))
    out.alpha_composite(menu, (0, 0))
    head = s.head("listen1", scale)
    out.alpha_composite(head, (menu.width + 6, menu.height // 2 - head.height // 2))
    return out


def save(image, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    image.convert("RGB").save(path, optimize=True)
    print(os.path.relpath(path, s.ROOT))


def hero():
    canvas = sky()
    s.sparkle(canvas, (70, 690), 60, angle=-72)
    s.sparkle(canvas, (650, 70), 40, rays=8)
    title(canvas, "Copy anything.\nHear what matters.",
          "AI summaries and text to speech, one tap away on iPhone, Mac and Windows.", y=70, size=56, width=360)
    for i, (label, x) in enumerate([("iPhone", 60), ("Mac", 178), ("Windows", 268)]):
        f = s.font("Inter-SemiBold.ttf", 20)
        wdt = f.getlength(label) + 36
        chip = s.layer((W, H), s.WHITE)
        ImageDraw.Draw(chip).rounded_rectangle([x, 330, x + wdt, 374], radius=22, fill=(255, 255, 255, 60),
                                               outline=(255, 255, 255, 150), width=2)
        canvas.alpha_composite(chip)
        ImageDraw.Draw(canvas).text((x + wdt / 2, 352), label, font=f, fill=s.WHITE, anchor="mm")
    win = chat_window((590, 430), "mac")
    place(canvas, win, 650, 250)
    place(canvas, pill(), 660, 196, blur=14)
    place(canvas, shiba_menu(), 960, 556, blur=14)
    phone, pad = s.device(s.hero_screen("Tap your\nDynamic Island.\nStart listening.",
                                        "Notchman finds your long message, sums it up, and reads it out loud.", "listen1"), 215)
    canvas.alpha_composite(phone, (440 - pad, 232 - pad))
    save(canvas, "1-hero.png")


def mac():
    canvas = sky()
    title(canvas, "On your Mac:\ntap the Shiba", "It floats over any app. Select text, tap TL;DR, and keep working while it talks.",
          y=80, size=50, width=420)
    s.sparkle(canvas, (90, 680), 50, angle=-72)
    win = chat_window((700, 500), "mac")
    place(canvas, win, 500, 120)
    place(canvas, shiba_menu(), 900, 520, blur=14)
    place(canvas, pill(), 540, 60, blur=14)
    save(canvas, "2-mac.png")


def windows():
    canvas = sky()
    title(canvas, "On Windows:\nAlt+T for a TL;DR", "Works in your browser, Outlook, Slack, PDFs and AI chats.",
          y=80, size=50, width=420)
    s.sparkle(canvas, (1210, 60), 46, rays=8)
    win = email_window((700, 460), "windows")
    place(canvas, win, 500, 160)
    place(canvas, pill(), 560, 96, blur=14)
    key = s.layer((W, H))
    d = ImageDraw.Draw(key)
    for i, label in enumerate(["Alt", "T"]):
        x = 60 + i * 150
        d.rounded_rectangle([x, 380, x + 96, 460], radius=16, fill=(255, 255, 255, 255))
        d.text((x + 48, 420), label, font=s.font("InterDisplay-Bold.ttf", 32), fill=INK, anchor="mm")
    place(canvas, key.crop((0, 0, W, H)), 0, 0, blur=12, opacity=60)
    ImageDraw.Draw(canvas).text((183, 420), "+", font=s.font("InterDisplay-Bold.ttf", 34), fill=s.WHITE, anchor="mm")
    save(canvas, "3-windows.png")


def pick():
    canvas = sky()
    title(canvas, "Pick anything\non screen", "Can't copy it? Draw around any text, even in images and videos, and hear it.",
          y=80, size=50, width=420)
    shot = Image.open(os.path.join(UI, "10-picker-ready.png")).convert("RGBA").crop((330, 0, 1500, 440))
    shot = shot.resize((720, round(440 * 720 / 1170)), Image.LANCZOS)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius=14, fill=255)
    shot.putalpha(mask)
    place(canvas, shot, 500, 210)
    save(canvas, "4-pick-on-screen.png")


def voices():
    canvas = sky()
    title(canvas, "Natural voices,\nyour speed", "Nine voices, 0.75× to 2×. Free to start; Pro from $4.99 a month.",
          y=80, size=50, width=420)
    shot = Image.open(os.path.join(UI, "6-settings.png")).convert("RGBA")
    shot = shot.resize((700, round(shot.height * 700 / shot.width)), Image.LANCZOS).crop((0, 0, 700, 470))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius=14, fill=255)
    shot.putalpha(mask)
    place(canvas, shot, 510, 150)
    save(canvas, "5-voices.png")


def iphone():
    canvas = sky()
    title(canvas, "On iPhone: it lives\nin your Dynamic Island",
          "Copy anything in any app, tap the Shiba, hear the TL;DR. No need to open Notchman.", y=110, size=48, width=470)
    s.sparkle(canvas, (90, 660), 50, angle=-72)
    for i, (screen, x, y) in enumerate([("shiba/player", 860, 120), (None, 600, 70)]):
        img = s.app_screen(screen) if screen else s.hero_screen(
            "Tap your\nDynamic Island.\nStart listening.",
            "Notchman finds your long message, sums it up, and reads it out loud.", "listen1")
        phone, pad = s.device(img, 290)
        canvas.alpha_composite(phone, (x - pad, y - pad))
    save(canvas, "6-iphone.png")


def thumbnail():
    icon = Image.open(os.path.join(s.ROOT, "design/art/app-icon.png")).convert("RGB").resize((240, 240), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    icon.save(os.path.join(OUT, "thumbnail.png"))
    print("docs/producthunt/thumbnail.png")


if __name__ == "__main__":
    hero()
    mac()
    windows()
    pick()
    voices()
    iphone()
    thumbnail()
