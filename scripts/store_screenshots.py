#!/usr/bin/env python3
"""App Store screenshots (6.9-inch iPhone, 1320×2868), made from the simulator
screenshots in docs/screenshots (Actions → Screenshots).

Each one: a short headline that says what Notchman does in words people
search for (Apple reads screenshot text for search, so it's high-contrast and
specific), a line under it, the real screen in an iPhone that runs off the
bottom, and sometimes a piece of the real UI enlarged on top (the Dynamic
Island buttons, the key points) or the Shiba's head.

  python3 scripts/store_screenshots.py      writes docs/store/main/01-….png and
                                            docs/store/<page>/01-….png for each
                                            custom product page (PAGES)

The main page's order is the order on the App Store: the first three are
what most people see. A custom product page uses its own first three, then
main 04–07 (see docs/APP_STORE_LAUNCH.md).
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SIZE = (1320, 2868)
SOURCE = os.path.join(ROOT, "docs/screenshots")
OUT = os.path.join(ROOT, "docs/store")
STORE = os.path.join(ROOT, "design/store")
HEADS = os.path.join(ROOT, "desktop/assets/shiba-head-sprites.png")
HEAD_FRAMES = ["idle", "blink", "listen1", "listen2", "think1", "think2", "talk1", "talk2", "happy"]

NAVY = (11, 31, 68)
WHITE = (255, 255, 255)
THEMES = {
    # The app's sky.
    "sky": {"stops": [(0.0, (124, 192, 244)), (0.45, (190, 225, 250)), (1.0, (236, 247, 255))],
            "text": NAVY, "sub": (32, 58, 104)},
    # Deeper blue, white text: for the first screenshot and a change of pace.
    "deep": {"stops": [(0.0, (20, 92, 214)), (0.5, (60, 150, 240)), (1.0, (150, 208, 248))],
             "text": WHITE, "sub": (225, 238, 255)},
}

# Pieces of real screens to enlarge on top (x0, y0, x1, y1 in the 1320×2868 screenshots).
ISLAND = ("onboardingTry", (70, 1058, 1252, 1442), 140)   # the Dynamic Island's TL;DR / Read
KEY_POINTS = ("keyPoints", (40, 420, 1280, 1500), 44)        # the numbered key points

# The main product page. (screen, headline, line under it, theme, extras)
MAIN = [
    ("player", "Too long?\nHear the TL;DR", "AI summary of any text, read aloud", "deep",
     {"callout": ISLAND, "at": 745, "width": 960}),
    ("onboardingTry", "Summarize from\nthe Dynamic Island", "Copy anything. Hold the Shiba. Tap TL;DR.", "sky", {}),
    ("player", "Every key point,\nname and number", "From long articles, papers and emails", "sky",
     {"callout": KEY_POINTS, "at": 1780, "width": 1100}),
    ("fullread", "Text to speech in\na natural voice", "Or hear every word, read aloud", "sky", {}),
    ("generating", "AI finds what\nmatters in seconds", "Posts and article links are read for you", "deep", {}),
    ("home", "Messages, emails,\narticles, AI answers", "Share to Notchman from any app", "sky", {}),
    ("history", "Your listens stay\non your iPhone", "Private by design. No account needed.", "sky", {}),
]

# Custom product pages: a first three for one kind of person (they link from
# ads, posts or search keywords), then main 04–07.
PAGES = {
    "study": [
        ("player", "Study smarter:\nhear the key points", "Long readings and papers, summarized", "deep",
         {"callout": KEY_POINTS, "at": 1780, "width": 1100}),
        ("generating", "Long readings,\nsummarized in seconds", "Paste text or share a link", "sky", {}),
        ("player", "Revise on the go,\nscreen off", "Listen while you walk or commute", "sky", {}),
    ],
    "work": [
        ("home", "Long emails?\nHear the gist", "Emails, chats and docs in seconds", "deep", {}),
        ("player", "Every name, date\nand number kept", "Nothing important left out", "sky",
         {"callout": KEY_POINTS, "at": 1780, "width": 1100}),
        ("onboardingTry", "One tap from\nany app", "Hold the Shiba in the Dynamic Island", "sky", {}),
    ],
    "focus": [
        ("player", "Too much to read?\nListen instead", "Every long text, as a short TL;DR", "deep",
         {"mascot": "happy", "mascot_at": (1120, 700)}),
        ("fullread", "Hear every word,\nat your speed", "A calm, natural voice reads it all", "sky", {}),
        ("onboardingTry", "No more walls\nof text", "Copy it. Hold the Shiba. Tap TL;DR.", "sky", {}),
    ],
    "ai": [
        ("player", "Long AI answers?\nHear the TL;DR", "Every key point, in seconds", "deep",
         {"callout": ISLAND, "at": 745, "width": 960}),
        ("player", "Just the key points,\nnot the essay", "Numbers and steps kept exactly", "sky",
         {"callout": KEY_POINTS, "at": 1780, "width": 1100}),
        ("fullread", "Or hear the whole\nanswer read aloud", "Natural voice, in its language", "sky", {}),
    ],
    "shiba": [
        ("player", "Meet the Shiba\nthat reads for you", "Copy any text, hear what matters", "deep",
         {"mascot": "listen1", "mascot_at": (1120, 700)}),
        ("onboardingTry", "It lives in your\nDynamic Island", "Hold the Shiba, tap TL;DR", "sky", {}),
        ("player", "TL;DRs that keep\nevery key point", "Messages, articles, AI answers", "sky",
         {"callout": KEY_POINTS, "at": 1780, "width": 1100}),
    ],
}


def font(name, size):
    return ImageFont.truetype(os.path.join(STORE, name), size)


def gradient(size, stops):
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


CLOUD = ["....XXXX......",
         "..XXXXXXXX.XX.",
         ".XXXXXXXXXXXXX",
         "XXXXXXXXXXXXXX"]
SPARKLE = [".X.", "XXX", ".X."]


def pixels(pattern, cell, color):
    image = Image.new("RGBA", (len(pattern[0]) * cell, len(pattern) * cell), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for j, row in enumerate(pattern):
        for i, v in enumerate(row):
            if v == "X":
                draw.rectangle([i * cell, j * cell, (i + 1) * cell - 1, (j + 1) * cell - 1], fill=color)
    return image


def background(theme, seed):
    image = gradient(SIZE, THEMES[theme]["stops"]).convert("RGBA")
    # A few pixel clouds and sparkles, like the app's sky (placed per screenshot).
    clouds = [(-60, 640, 16), (980, 880, 14), (40, 1900, 12), (1000, 2350, 13)]
    sparkles = [(60, 80, 10), (1236, 560, 10), (1210, 1500, 9), (52, 1300, 10), (1180, 2100, 10)]
    for n, (x, y, cell) in enumerate(clouds):
        if (n + seed) % 2:
            continue
        image.alpha_composite(pixels(CLOUD, cell, (255, 255, 255, 120)), (x, y))
    for n, (x, y, cell) in enumerate(sparkles):
        if (n + seed) % 3 == 2:
            continue
        image.alpha_composite(pixels(SPARKLE, cell, (255, 255, 255, 190)), (x, y))
    return image


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.width - 1, image.height - 1], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def shadowed(image, blur=40, offset=(0, 30), opacity=90):
    """The image on a soft shadow, with room around it for the blur."""
    pad = blur * 2
    out = Image.new("RGBA", (image.width + 2 * pad, image.height + 2 * pad + offset[1]), (0, 0, 0, 0))
    shadow = Image.new("RGBA", image.size, (11, 31, 68, opacity))
    shadow.putalpha(image.getchannel("A").point(lambda a: a * opacity // 255))
    out.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(image, (pad, pad))
    return out, pad


def phone(shot, width):
    """The screenshot in an iPhone: a thin black bezel and a graphite edge."""
    screen = shot.resize((width, round(shot.height * width / shot.width)), Image.LANCZOS)
    radius = round(width * 0.135)
    bezel, edge = round(width * 0.024), round(width * 0.007)
    w, h = screen.width + 2 * (bezel + edge), screen.height + 2 * (bezel + edge)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius + bezel + edge, fill=(58, 64, 74, 255))
    draw.rounded_rectangle([edge, edge, w - 1 - edge, h - 1 - edge], radius=radius + bezel, fill=(8, 8, 10, 255))
    body.alpha_composite(rounded(screen, radius), (bezel + edge, bezel + edge))
    return body


def mascot(frame, height):
    sheet = Image.open(HEADS).convert("RGBA")
    cell = sheet.width // len(HEAD_FRAMES)
    head = sheet.crop((HEAD_FRAMES.index(frame) * cell, 0, (HEAD_FRAMES.index(frame) + 1) * cell, sheet.height))
    scale = height // head.height
    return head.resize((head.width * scale, head.height * scale), Image.NEAREST)


def fit(text, name, start, width, smallest):
    for size in range(start, smallest, -2):
        f = font(name, size)
        if all(f.getlength(line) <= width for line in text.split("\n")):
            return f
    return font(name, smallest)


def compose(screen, headline, line, theme, extras, seed):
    canvas = background(theme, seed)
    colors = THEMES[theme]
    draw = ImageDraw.Draw(canvas)
    head_font = fit(headline, "InterDisplay-ExtraBold.ttf", 124, SIZE[0] - 150, 80)
    draw.multiline_text((SIZE[0] / 2, 150), headline, font=head_font, fill=colors["text"], anchor="ma", align="center", spacing=18)
    top = 150 + len(headline.split("\n")) * (head_font.size + 18) + 22
    draw.text((SIZE[0] / 2, top), line, font=fit(line, "Inter-SemiBold.ttf", 54, SIZE[0] - 170, 38), fill=colors["sub"], anchor="ma")

    # The phone, running off the bottom.
    device, pad = shadowed(phone(Image.open(os.path.join(SOURCE, f"{screen}.png")).convert("RGB"), 1000), blur=36, opacity=70)
    canvas.alpha_composite(device, ((SIZE[0] - device.width) // 2, 700 - pad))

    if "callout" in extras:
        name, box, radius = extras["callout"]
        piece = Image.open(os.path.join(SOURCE, f"{name}.png")).convert("RGB").crop(box)
        width = extras["width"]
        piece = rounded(piece.resize((width, round(piece.height * width / piece.width)), Image.LANCZOS),
                        round(radius * width / piece.width))
        card, cpad = shadowed(piece, blur=30, offset=(0, 24), opacity=110)
        canvas.alpha_composite(card, ((SIZE[0] - card.width) // 2, extras["at"] - cpad))
    if "mascot" in extras:
        art = mascot(extras["mascot"], 260)
        x, y = extras["mascot_at"]
        canvas.alpha_composite(art, (x - art.width // 2, y - art.height // 2))
    return canvas.convert("RGB")


def write(folder, shots, offset=0):
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):
        if old.endswith(".png"):
            os.remove(os.path.join(folder, old))
    for index, (screen, headline, line, theme, extras) in enumerate(shots, 1):
        path = os.path.join(folder, f"{index:02d}-{screen}.png")
        compose(screen, headline, line, theme, extras, index + offset).save(path, optimize=True)
        print(os.path.relpath(path, ROOT))


def main():
    for old in os.listdir(OUT):
        if old.endswith(".png"):  # the earlier flat layout
            os.remove(os.path.join(OUT, old))
    write(os.path.join(OUT, "main"), MAIN)
    for n, (page, shots) in enumerate(PAGES.items()):
        write(os.path.join(OUT, page), shots, offset=n)


if __name__ == "__main__":
    main()
