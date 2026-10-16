#!/usr/bin/env python3
"""App Store screenshots: 1320×2868 (6.9-inch iPhone), four per page.

The look: an iPhone (titanium rim, black bezel, Dynamic Island) on a blue
sky with sparkles. Screenshot 1 shows the Shiba peeking over a big Dynamic
Island on the iPhone's screen, like the app's welcome. Screenshots 2–4 put a
real screen from the app under a headline, with the Shiba's head peeking over
the iPhone.

The app's screens come from the Screenshots workflow: docs/screenshots, and
docs/screenshots/<audience> with that audience's sample texts.

  python3 scripts/store_screenshots.py           every page → docs/store/<page>/1-….png … 4-….png
  python3 scripts/store_screenshots.py study     one page

"main" is the default product page; the others are custom product pages
(docs/APP_STORE_LAUNCH.md). Headlines use the words people search for
(Apple reads screenshot text).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SIZE = (1320, 2868)        # the App Store screenshot, and the app's own screenshots
SHOTS = os.path.join(ROOT, "docs/screenshots")
OUT = os.path.join(ROOT, "docs/store")
FONTS = os.path.join(ROOT, "design/store")
HEADS = os.path.join(ROOT, "desktop/assets/shiba-head-sprites.png")
HEAD_FRAMES = ["idle", "blink", "listen1", "listen2", "think1", "think2", "talk1", "talk2", "happy"]

NAVY = (14, 30, 66)
GRAY = (92, 106, 132)
WHITE = (255, 255, 255)
OUTLINE = (11, 26, 66)     # the Shiba's outline and fur, as in the sprites
FUR = (248, 248, 248)
SKY = [(0.0, (31, 112, 230)), (0.35, (70, 141, 235)), (0.72, (136, 187, 247)), (1.0, (194, 226, 255))]
SCREEN_SKY = [(0.0, (150, 206, 252)), (0.3, (178, 222, 254)), (0.5, (228, 243, 254)), (1.0, (249, 252, 255))]
TITANIUM = np.array([234, 226, 240], dtype=np.float32)

# Where things are on a 1320×2868 iPhone screen.
ISLAND = (468, 38, 852, 155)   # the Dynamic Island, a little bigger than the real one

# Each page: the hero's headline, line and Shiba face, then three (headline, line, screen, Shiba face).
# A screen is "<audience>/<name>" from docs/screenshots.
PAGES = {
    "main": (("Tap your\nDynamic Island.\nStart listening.",
              "Notchman finds your long message, sums it up, and reads it out loud.", "listen1"), [
        ("Too long?\nHear the TL;DR", "AI summary of any text, read aloud", "shiba/player", "talk1"),
        ("Every key point,\nname and number", "Summarize emails, papers and AI answers", "work/keyPoints", "happy"),
        ("Text to speech\nfor anything", "Copy it, tap the Shiba, listen", "study/home", "listen1"),
    ]),
    "study": (("Tap your\nDynamic Island.\nHear your reading.",
               "Notchman turns long readings and research papers into key points, read out loud.", "listen1"), [
        ("Study smarter:\nhear the key points", "Research papers and readings, summarized", "study/player", "talk1"),
        ("Every fact and\nnumber, kept", "Key points to review before the exam", "study/keyPoints", "happy"),
        ("Revise on\nthe go", "Lecture notes and papers, read aloud", "study/home", "listen1"),
    ]),
    "work": (("Tap your\nDynamic Island.\nHear the gist.",
              "Notchman sums up long emails and threads, and reads them out loud.", "listen1"), [
        ("Long emails?\nHear the gist", "Emails, threads and docs, summarized", "work/player", "talk1"),
        ("Every date and\nnumber, kept", "The five things that matter, in seconds", "work/keyPoints", "happy"),
        ("Clear your inbox\nby ear", "Listen between meetings", "work/home", "listen1"),
    ]),
    "focus": (("Tap your\nDynamic Island.\nLet it read to you.",
               "Notchman sums up any wall of text and reads it out loud.", "listen1"), [
        ("Too much to read?\nListen instead", "Any long text, as a short TL;DR", "focus/player", "talk1"),
        ("One line\nper key point", "Easy to scan, easy to remember", "focus/keyPoints", "happy"),
        ("It finds what\nmatters for you", "Articles, emails and messages, in seconds", "focus/generating", "think1"),
    ]),
    "ai": (("Tap your\nDynamic Island.\nHear the TL;DR.",
            "Copy a long AI answer. Notchman sums it up and reads it out loud.", "listen1"), [
        ("Long AI answers?\nHear the TL;DR", "Copy the answer, hear what matters", "ai/player", "talk1"),
        ("Just the key points,\nnot the essay", "Steps, prices and times kept exactly", "ai/keyPoints", "happy"),
        ("Every answer,\nsaved for later", "Replay anything from your history", "ai/history", "listen1"),
    ]),
    "shiba": (("Meet the Shiba\nthat reads\nfor you.",
               "It lives in your Dynamic Island. Copy anything, tap it, and listen.", "happy"), [
        ("Long group chat?\nHear the TL;DR", "Copy it, tap the Shiba, listen", "shiba/player", "talk1"),
        ("Who, when, where\nand how much", "Every key point, kept", "shiba/keyPoints", "happy"),
        ("It thinks,\nthen it talks", "Finds what matters in seconds", "shiba/generating", "think1"),
    ]),
}


# --- Basics ----------------------------------------------------------------------

def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def gradient(size, stops):
    """A top-to-bottom gradient through (position 0…1, color) stops."""
    w, h = size
    t = np.linspace(0, 1, h)
    rows = np.stack([np.interp(t, [p for p, _ in stops], [c[i] for _, c in stops]) for i in range(3)], axis=1)
    return Image.fromarray(np.repeat(rows[:, None, :], w, axis=1).round().astype(np.uint8), "RGB").convert("RGBA")


def coverage(sd):
    """Anti-aliased coverage (0…1) from a signed distance in pixels (negative inside)."""
    return np.clip(0.5 - sd, 0, 1)


def rounded_box(w, h, box, r):
    """Signed distance to a rounded rectangle (x0, y0, x1, y1) on a w×h grid, and its outward normal."""
    x0, y0, x1, y1 = box
    y, x = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    qx = np.abs(x - cx) - ((x1 - x0) / 2 - r)
    qy = np.abs(y - cy) - ((y1 - y0) / 2 - r)
    ox, oy = np.maximum(qx, 0), np.maximum(qy, 0)
    corner = np.hypot(ox, oy)
    sd = corner + np.minimum(np.maximum(qx, qy), 0) - r
    sx, sy = np.sign(x - cx), np.sign(y - cy)
    safe = np.maximum(corner, 1e-6)
    in_corner = (qx > 0) & (qy > 0)
    nx = np.where(in_corner, ox / safe, (qx >= qy).astype(np.float32)) * sx
    ny = np.where(in_corner, oy / safe, (qy > qx).astype(np.float32)) * sy
    return sd, nx, ny


def layer(size, color=(0, 0, 0)):
    """A clear layer. Things blurred later are drawn on a clear layer of their own color, so
    their soft edges don't turn gray."""
    return Image.new("RGBA", size, color + (0,))


def shadowed(image, blur, offset, opacity, color=(8, 30, 84)):
    """`image` over its own soft shadow. Returns (image, padding added on each side)."""
    pad = blur * 3
    out = layer((image.width + 2 * pad, image.height + 2 * pad))
    shadow = Image.new("RGBA", image.size, color + (0,))
    shadow.putalpha(image.getchannel("A").point(lambda a: a * opacity // 255))
    out.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(image, (pad, pad))
    return out, pad


# --- The iPhone --------------------------------------------------------------------

def titanium(sd, nx, ny, width):
    """The rim's colors: a dark outer edge, a bright bevel, a softer band, a dark line by the glass."""
    t = np.clip(-sd / width, 0, 1)
    shade = np.interp(t, [0, 0.07, 0.2, 0.5, 0.7, 0.88, 1], [0.3, 0.56, 0.98, 0.93, 0.74, 0.55, 0.24])
    # Light from the top left: brighter there, a little darker on the bottom right.
    shade = shade * (1 + 0.1 * (-0.55 * nx - 0.83 * ny))
    # Glints where the corners catch the light.
    angle = np.arctan2(ny, nx)
    band = (t > 0.18) & (t < 0.6)
    for centre, strength in [(-2.36, 0.35), (0.79, 0.18)]:
        d = np.angle(np.exp(1j * (angle - centre)))
        shade = shade + band * strength * np.exp(-(d ** 2) / (2 * 0.16 ** 2))
    return np.clip(shade[..., None] * TITANIUM, 0, 255)


def frame_ring(size, box, radius, rim, bezel, glass=None):
    """An iPhone frame (titanium rim and black bezel) as RGBA, with the screen inside left clear."""
    w, h = size
    sd, nx, ny = rounded_box(w, h, box, radius)
    rgb = titanium(sd, nx, ny, rim)
    inner = sd + rim                       # < 0 inside the rim: the black bezel
    black = coverage(inner)[..., None]
    rgb = rgb * (1 - black) + np.array([7, 7, 9], dtype=np.float32) * black
    # The edge of the glass: a faint line just inside the rim.
    line = np.clip(1 - np.abs(inner + 1.6) / 1.2, 0, 1)[..., None] * 0.5
    rgb = rgb * (1 - line) + np.array([58, 58, 66], dtype=np.float32) * line
    alpha = coverage(sd)
    if glass is not None:
        alpha = alpha * (1 - coverage(glass))
    out = np.dstack([rgb, alpha * 255]).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def side_buttons(size, body, rim, depth):
    """Action and volume buttons on the left, the side button on the right."""
    w, h = size
    x0, y0, x1, y1 = body
    out = np.zeros((h, w, 4), dtype=np.float32)
    height = y1 - y0
    y, x = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    for side, start, length in [(0, 0.168, 0.034), (0, 0.228, 0.062), (0, 0.305, 0.062), (1, 0.258, 0.098)]:
        top, bottom = y0 + height * start, y0 + height * (start + length)
        box = (x0 - depth, top, x0 + rim, bottom) if side == 0 else (x1 - rim, top, x1 + depth, bottom)
        sd, _, _ = rounded_box(w, h, box, depth * 0.9)
        # Rounded across: dark at the outer edge, bright in the middle.
        across = np.clip((x - (x0 - depth)) / depth if side == 0 else ((x1 + depth) - x) / depth, 0, 1)
        shade = np.interp(across, [0, 0.25, 0.6, 1], [0.38, 0.86, 0.72, 0.55])
        a = coverage(sd)
        out[..., :3] += (shade[..., None] * TITANIUM) * a[..., None]
        out[..., 3] += a * 255
    out[..., :3] /= np.maximum(out[..., 3:4] / 255, 1e-6)
    return Image.fromarray(np.clip(out, 0, 255).round().astype(np.uint8), "RGBA")


def island(size, box, camera=True):
    """The Dynamic Island: a black pill, with the camera at its right end."""
    w, h = size
    x0, y0, x1, y1 = box
    r = (y1 - y0) / 2
    sd, _, _ = rounded_box(w, h, box, r)
    out = Image.new("RGBA", size, (0, 0, 0, 255))
    out.putalpha(Image.fromarray((coverage(sd) * 255).round().astype(np.uint8), "L"))
    if not camera:
        return out
    draw = ImageDraw.Draw(out)
    cx, cy = x1 - r, (y0 + y1) / 2
    for scale, color in [(0.36, (20, 22, 32, 255)), (0.24, (34, 40, 66, 255)), (0.14, (10, 12, 22, 255))]:
        draw.ellipse([cx - r * scale, cy - r * scale, cx + r * scale, cy + r * scale], fill=color)
    draw.ellipse([cx - r * 0.12, cy - r * 0.16, cx - r * 0.02, cy - r * 0.06], fill=(70, 86, 140, 255))
    return out


def iphone(screen, screen_width):
    """`screen` (1320×2868) in an iPhone whose screen is `screen_width` px wide."""
    s = screen_width
    scale = s / SIZE[0]
    sh = s * SIZE[1] / SIZE[0]
    rim, bezel, depth = 0.0135 * s, 0.029 * s, 0.0085 * s
    radius = 0.138 * s
    edge = rim + bezel
    w = math.ceil(s + 2 * edge + 2 * depth)
    h = math.ceil(sh + 2 * edge)
    body = (depth, 0, depth + s + 2 * edge, sh + 2 * edge)
    glass_box = (body[0] + edge, edge, body[2] - edge, body[3] - edge)
    glass, _, _ = rounded_box(w, h, glass_box, radius)

    out = side_buttons((w, h), body, rim, depth)
    # The screen, under the frame (a pixel bigger, so no seam shows).
    picture = screen.convert("RGB").resize((round(s), round(sh)), Image.LANCZOS)
    placed = layer((w, h))
    placed.paste(picture, (round(glass_box[0]), round(glass_box[1])))
    placed.putalpha(Image.fromarray((coverage(glass - 1.2) * 255).round().astype(np.uint8), "L"))
    out.alpha_composite(placed)
    out.alpha_composite(frame_ring((w, h), body, radius + edge, rim, bezel, glass))
    ix0, iy0, ix1, iy1 = ISLAND
    out.alpha_composite(island((w, h), (glass_box[0] + ix0 * scale, glass_box[1] + iy0 * scale,
                                        glass_box[0] + ix1 * scale, glass_box[1] + iy1 * scale)))
    return out


def device(screen, screen_width):
    """The iPhone with its shadow. Returns (image, padding around the iPhone)."""
    phone = iphone(screen, screen_width)
    soft, pad = shadowed(phone, 46, (0, 44), 105)
    contact, cpad = shadowed(phone, 10, (0, 10), 60)
    soft.alpha_composite(contact, (pad - cpad, pad - cpad))
    return soft, pad


# --- The Shiba ----------------------------------------------------------------------

PAW = [".OOOOO.",
       "OWWWWWO",
       "OWOWOWO"]


def head(face, scale):
    sheet = Image.open(HEADS).convert("RGBA")
    cell = sheet.width // len(HEAD_FRAMES)
    i = HEAD_FRAMES.index(face)
    art = sheet.crop((i * cell, 0, (i + 1) * cell, sheet.height))
    return art.resize((art.width * scale, art.height * scale), Image.NEAREST)


def paw(scale):
    out = layer((len(PAW[0]) * scale, len(PAW) * scale))
    draw = ImageDraw.Draw(out)
    for j, row in enumerate(PAW):
        for i, v in enumerate(row):
            if v != ".":
                draw.rectangle([i * scale, j * scale, (i + 1) * scale - 1, (j + 1) * scale - 1],
                               fill=(OUTLINE if v == "O" else FUR) + (255,))
    return out


def peek(canvas, edge_y, center_x, scale, face, behind, grip):
    """The Shiba's head peeking over an edge at `edge_y`, its paws `grip` px over it.

    `behind()` draws what it hides behind: after the head, before the paws."""
    art = head(face, scale)
    canvas.alpha_composite(art, (round(center_x - art.width / 2), round(edge_y + 2 * scale - art.height)))
    behind()
    hand = paw(scale)
    for x in (center_x - art.width / 2 + scale * 0.5, center_x + art.width / 2 - hand.width - scale * 0.5):
        canvas.alpha_composite(hand, (round(x), round(edge_y + grip - hand.height)))
    return art


def listening_lines(canvas, x, y, unit):
    """Three short strokes by the perked ear: it hears you."""
    lines = layer(canvas.size)
    draw = ImageDraw.Draw(lines)
    for (dx0, dy0, dx1, dy1) in [(0.0, 1.6, 0.35, 0.0), (0.9, 2.3, 1.7, 1.2), (1.2, 3.4, 2.2, 3.1)]:
        a, b = (x + dx0 * unit, y + dy0 * unit), (x + dx1 * unit, y + dy1 * unit)
        draw.line([a, b], fill=OUTLINE + (255,), width=round(unit * 0.42))
        draw.line([a, b], fill=WHITE + (255,), width=round(unit * 0.24))
    canvas.alpha_composite(lines)


def ripple(canvas, center, r):
    """A tap: a blue dot in soft rings."""
    x, y = center
    box = (round(x - r * 2.4), round(y - r * 2.4), round(x + r * 2.4), round(y + r * 2.4))
    rings = layer((box[2] - box[0], box[3] - box[1]))
    draw = ImageDraw.Draw(rings)
    c = rings.width / 2
    draw.ellipse([c - r * 2.1, c - r * 2.1, c + r * 2.1, c + r * 2.1], fill=(255, 255, 255, 46),
                 outline=(255, 255, 255, 120), width=max(2, round(r * 0.08)))
    draw.ellipse([c - r * 1.55, c - r * 1.55, c + r * 1.55, c + r * 1.55], fill=(235, 242, 252, 215),
                 outline=(160, 176, 200, 255), width=max(2, round(r * 0.1)))
    shaded, pad = shadowed(rings, round(r * 0.3), (0, round(r * 0.2)), 70)
    canvas.alpha_composite(shaded, (box[0] - pad, box[1] - pad))
    dot = gradient((round(2 * r), round(2 * r)), [(0, (92, 178, 255)), (1, (20, 112, 228))])
    mask = Image.new("L", dot.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, dot.width - 1, dot.height - 1], fill=255)
    dot.putalpha(mask)
    canvas.alpha_composite(dot, (round(x - r), round(y - r)))


# --- Sky -----------------------------------------------------------------------------

def cloud(width, tint=(206, 226, 248)):
    """A soft cartoon cloud, `width` px wide."""
    s = 2
    w, h = width * s, round(width * 0.6) * s
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    for cx, cy, r in [(0.24, 0.64, 0.19), (0.42, 0.44, 0.24), (0.63, 0.5, 0.21), (0.8, 0.68, 0.15)]:
        draw.ellipse([(cx - r) * w, cy * h - r * w, (cx + r) * w, cy * h + r * w], fill=255)
    draw.rounded_rectangle([0.08 * w, 0.6 * h, 0.92 * w, 0.96 * h], radius=0.18 * h, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(s * 1.2))
    art = gradient((w, h), [(0, WHITE), (0.5, WHITE), (1, tint)])
    art.putalpha(mask)
    return art.resize((width, h // s), Image.LANCZOS)


def sparkle(canvas, center, size, angle=0.0, rays=4, opacity=255):
    """A glowing star: long thin rays and a bright middle."""
    x, y = center
    art = layer(canvas.size, WHITE)
    draw = ImageDraw.Draw(art)
    for k in range(rays):
        a = math.radians(angle + k * 360 / rays)
        length = size * (1 if k % 2 == 0 else 0.78) * (1 if rays == 4 or k % 2 == 0 else 0.6)
        width = size * 0.05
        tip = (x + length * math.cos(a), y + length * math.sin(a))
        sides = [(x + width * math.cos(a + s), y + width * math.sin(a + s)) for s in (math.pi / 2, -math.pi / 2)]
        draw.polygon([sides[0], tip, sides[1]], fill=(255, 255, 255, opacity))
    halo = layer(canvas.size, WHITE)
    ImageDraw.Draw(halo).ellipse([x - size * 0.3, y - size * 0.3, x + size * 0.3, y + size * 0.3],
                                 fill=(255, 255, 255, round(opacity * 0.75)))
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(size * 0.2)))
    canvas.alpha_composite(art.filter(ImageFilter.GaussianBlur(max(1, size * 0.008))))
    canvas.alpha_composite(art.filter(ImageFilter.GaussianBlur(size * 0.04)))
    core = layer(canvas.size, WHITE)
    ImageDraw.Draw(core).ellipse([x - size * 0.06, y - size * 0.06, x + size * 0.06, y + size * 0.06], fill=WHITE + (255,))
    canvas.alpha_composite(core.filter(ImageFilter.GaussianBlur(size * 0.02)))


def swoosh(canvas, start):
    """A soft cloud in the bottom left corner, and a thin trail of light from it up to `start`."""
    w, h = canvas.size
    puffs = layer(canvas.size, WHITE)
    draw = ImageDraw.Draw(puffs)
    for box in [(-300, h - 330, 300, h + 220), (-140, h - 210, 560, h + 260), (-320, h - 520, 150, h - 70)]:
        draw.ellipse(box, fill=(255, 255, 255, 255))
    canvas.alpha_composite(puffs.filter(ImageFilter.GaussianBlur(34)))
    # The trail: a curve out of the cloud, thin at its tip.
    sx, sy = start
    a, c = (150, h - 250), (sx * 0.55, sy + 210)
    top, bottom = [], []
    for i in range(61):
        t = i / 60
        px = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t ** 2 * sx
        py = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t ** 2 * sy
        half = 30 * (1 - t) ** 1.4 + 1.2
        top.append((px - half * 0.7, py - half * 0.7))
        bottom.append((px + half * 0.7, py + half * 0.7))
    trail = layer(canvas.size, WHITE)
    ImageDraw.Draw(trail).polygon(top + bottom[::-1], fill=(255, 255, 255, 235))
    canvas.alpha_composite(trail.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(trail.filter(ImageFilter.GaussianBlur(2)))


def background(trail_end):
    canvas = gradient(SIZE, SKY)
    light = layer(SIZE, WHITE)
    ImageDraw.Draw(light).ellipse([-300, -300, 700, 600], fill=(255, 255, 255, 46))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(160)))
    swoosh(canvas, trail_end)
    return canvas


# --- The status bar -------------------------------------------------------------------

def status_bar(canvas, color=(10, 14, 24)):
    """9:41, signal, Wi-Fi and a full battery, dark (as on a light screen)."""
    art = layer(canvas.size)
    draw = ImageDraw.Draw(art)
    ink = color + (255,)
    draw.text((246, 97), "9:41", font=font("Inter-SemiBold.ttf", 54), fill=ink, anchor="mm")
    for i in range(4):
        x = 940 + i * 16.3
        draw.rounded_rectangle([x, 116 - 16 - 8 * i, x + 12, 116], radius=2.5, fill=ink)
    cx, cy = 1053, 116
    wifi = Image.new("L", canvas.size, 0)
    wd = ImageDraw.Draw(wifi)
    for r, value in [(40, 255), (30, 0), (24, 255), (14, 0), (8, 255)]:
        wd.pieslice([cx - r, cy - r, cx + r, cy + r], 225, 315, fill=value)
    art.paste(Image.new("RGBA", canvas.size, ink), (0, 0), wifi)
    draw.rounded_rectangle([1104, 78, 1188, 115], radius=11, outline=color + (110,), width=4)
    draw.rounded_rectangle([1111, 85, 1181, 108], radius=6, fill=ink)
    draw.rounded_rectangle([1192, 90, 1198, 103], radius=3, fill=color + (110,))
    canvas.alpha_composite(art)


def home_indicator(canvas):
    ImageDraw.Draw(canvas).rounded_rectangle([450, 2823, 870, 2838], radius=8, fill=(10, 14, 24, 235))


# --- The app's screens ------------------------------------------------------------------

def app_screen(name):
    """A screen from docs/screenshots, made full-screen with a clean status bar.

    The player and key points open as sheets, black above the sheet: that top
    is filled with the sheet's own color."""
    pixels = np.array(Image.open(os.path.join(SHOTS, f"{name}.png")).convert("RGB"))
    if pixels[20, 660].sum() < 40:
        pixels[:250] = pixels[250, 660]       # the sheet's color, just above its buttons
    else:
        pixels[:190] = pixels[:190, 12:13]    # the sky behind the status bar
    screen = Image.fromarray(pixels).convert("RGBA")
    status_bar(screen)
    return screen


def text_lines(draw, lines, center_x, top, typeface, size, fill, leading):
    f = font(typeface, size)
    for i, line in enumerate(lines):
        draw.text((center_x, top + i * leading), line, font=f, fill=fill, anchor="ma")
    return top + len(lines) * leading


def fit(lines, typeface, largest, width):
    for size in range(largest, 40, -2):
        if all(font(typeface, size).getlength(line) <= width for line in lines):
            return size
    return 40


def wrap(text, typeface, size, width):
    """Lines no wider than `width`, as even in length as they can be."""
    def greedy(limit):
        f, lines, line = font(typeface, size), [], ""
        for word in text.split():
            trial = f"{line} {word}".strip()
            if line and f.getlength(trial) > limit:
                lines.append(line)
                line = word
            else:
                line = trial
        return lines + [line]
    lines = greedy(width)
    while width > 200 and len(greedy(width - 10)) == len(lines):
        width -= 10
    return greedy(width)


def hero_screen(headline, line, face):
    """The welcome-style screen: sky, the Shiba peeking over a big Dynamic Island, a tap."""
    w, h = SIZE
    screen = gradient(SIZE, SCREEN_SKY)
    for x, y, width in [(-70, 230, 360), (300, 520, 130), (-90, 690, 400), (1030, 270, 360), (1060, 840, 330),
                        (-40, 1300, 330), (1080, 1330, 300)]:
        screen.alpha_composite(cloud(width), (x, y))
    fog = Image.new("RGBA", (w, h - 1200), (250, 252, 255, 0))
    fog.putalpha(gradient((w, h - 1200), [(0, (0, 0, 0)), (0.28, (215, 215, 215)), (1, WHITE)]).getchannel("R"))
    screen.alpha_composite(fog, (0, 1200))

    # A big iPhone top; the frame fades out down its sides.
    top, rim, bezel = 1040, 15, 34
    box = (6, top, w - 6, top + 1200)
    edge = rim + bezel

    def frame():
        glass, _, _ = rounded_box(w, h, (box[0] + edge, top + edge, box[2] - edge, box[3] - edge), 250 - edge)
        ring = frame_ring((w, h), box, 250, rim, bezel, glass)
        fade = gradient((w, h), [(0, WHITE), ((top + 230) / h, WHITE), ((top + 470) / h, (0, 0, 0)), (1, (0, 0, 0))])
        alpha = np.array(ring.getchannel("A"), dtype=np.float32) * np.array(fade.getchannel("R"), dtype=np.float32) / 255
        ring.putalpha(Image.fromarray(alpha.round().astype(np.uint8), "L"))
        screen.alpha_composite(ring)
        screen.alpha_composite(island((w, h), (w / 2 - 310, top + edge + 12, w / 2 + 310, top + edge + 180), camera=False))

    scale = 18
    art = peek(screen, top, w / 2, scale, face, frame, rim + bezel * 0.6)
    if face.startswith("listen"):
        listening_lines(screen, w / 2 + art.width / 2 + 0.4 * scale, top - art.height + 1.6 * scale, scale * 2)
    ripple(screen, (w / 2 + 310 - 104, top + edge + 34), 34)

    draw = ImageDraw.Draw(screen)
    lines = headline.split("\n")
    size = fit(lines, "InterDisplay-ExtraBold.ttf", 132, 1120)
    y = text_lines(draw, lines, w / 2, 1440, "InterDisplay-ExtraBold.ttf", size, NAVY + (255,), round(size * 1.08))
    sub = wrap(line, "Inter-Medium.ttf", 52, 1080)
    text_lines(draw, sub, w / 2, y + 60, "Inter-Medium.ttf", 52, GRAY + (255,), 72)

    button = gradient((1120, 182), [(0, (86, 176, 252)), (1, (34, 136, 242))])
    mask = Image.new("L", button.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, button.width - 1, button.height - 1], radius=91, fill=255)
    button.putalpha(mask)
    ImageDraw.Draw(button).text((560, 92), "Got it", font=font("Inter-SemiBold.ttf", 64), fill=WHITE, anchor="mm")
    lifted, pad = shadowed(button, 24, (0, 16), 70, color=(30, 110, 220))
    screen.alpha_composite(lifted, (100 - pad, 2290 - pad))
    for i, x in enumerate((586, 660, 734)):
        color = (34, 128, 240) if i == 0 else (196, 208, 228)
        draw.ellipse([x - 16, 2620 - 16, x + 16, 2620 + 16], fill=color)

    status_bar(screen)
    home_indicator(screen)
    return screen


# --- The four screenshots -------------------------------------------------------------------

def hero_shot(headline, line, face):
    phone, pad = device(hero_screen(headline, line, face), 960)
    body_w, body_h = phone.width - 2 * pad, phone.height - 2 * pad
    x, y = (SIZE[0] - body_w) // 2, 358
    canvas = background((x + 0.12 * body_w, y + body_h - 60))
    sparkle(canvas, (132, 132), 190, angle=-72)
    sparkle(canvas, (1150, 2640), 74, angle=0, rays=8)
    canvas.alpha_composite(phone, (x - pad, y - pad))
    return canvas


def cloud_bank(canvas, top):
    """A sea of clouds from about `top` down: a bluish row behind, a white row in front."""
    w, h = canvas.size
    mist = Image.new("RGBA", (w, h - top + 80), (244, 249, 255, 0))
    mist.putalpha(gradient(mist.size, [(0, (0, 0, 0)), (0.12, (190, 190, 190)), (1, WHITE)]).getchannel("R"))
    canvas.alpha_composite(mist, (0, top - 80))
    rows = [
        (top + 160, [(40, 150), (290, 185), (560, 150), (820, 190), (1080, 160), (1300, 150)],
         [(0, (220, 234, 252)), (1, (236, 244, 255))], 3),
        (top + 420, [(-40, 200), (250, 230), (560, 205), (860, 240), (1150, 215), (1420, 200)],
         [(0, WHITE), (0.5, (246, 250, 255)), (1, (240, 246, 255))], 0),
    ]
    for line, bumps, colors, blur in rows:
        mask = Image.new("L", (w, h), 0)
        draw = ImageDraw.Draw(mask)
        for cx, r in bumps:
            draw.ellipse([cx - r, line - r, cx + r, line + r], fill=255)
        draw.rectangle([0, line, w, h], fill=255)
        # A soft blue shade just above each row, so the rows stand apart.
        shade = Image.new("RGBA", (w, h), (120, 160, 220, 0))
        shade.putalpha(mask.filter(ImageFilter.GaussianBlur(18)).point(lambda a: a * 50 // 255))
        canvas.alpha_composite(shade, (0, -12))
        clouds = gradient((w, h), [(0, colors[0][1]), ((line - 250) / h, colors[0][1])] +
                          [((line - 250) / h + p * (1 - (line - 250) / h), c) for p, c in colors[1:]])
        clouds.putalpha(mask.filter(ImageFilter.GaussianBlur(1.5 + blur)))
        canvas.alpha_composite(clouds)


def headline(canvas, lines, line, top, color, line_color, shadow, largest=120):
    """The headline and the line under it, centered."""
    size = fit(lines, "InterDisplay-ExtraBold.ttf", largest, 1120)
    words = layer(SIZE, color)
    draw = ImageDraw.Draw(words)
    bottom = text_lines(draw, lines, SIZE[0] / 2, top, "InterDisplay-ExtraBold.ttf", size, color + (255,), round(size * 1.08))
    sub_size = fit([line], "Inter-Medium.ttf", 48, 1120)
    text_lines(draw, [line], SIZE[0] / 2, bottom + 30, "Inter-Medium.ttf", sub_size, line_color, 60)
    if shadow:
        lift = Image.new("RGBA", SIZE, (8, 30, 84, 0))
        lift.putalpha(words.getchannel("A").point(lambda a: a * 60 // 255))
        canvas.alpha_composite(lift.filter(ImageFilter.GaussianBlur(14)), (0, 6))
    canvas.alpha_composite(words)


def phone_shot(title, line, screen_name, face):
    """Headline on top, then the whole iPhone with the Shiba peeking over it."""
    phone, pad = device(app_screen(screen_name), 862)
    body_w, body_h = phone.width - 2 * pad, phone.height - 2 * pad
    x, y = (SIZE[0] - body_w) // 2, 650
    canvas = background((x + 0.12 * body_w, y + body_h - 60))
    sparkle(canvas, (96, 1260), 120, angle=-72)
    sparkle(canvas, (1222, 2010), 64, angle=0, rays=8)
    sparkle(canvas, (1234, 92), 64, angle=-72, opacity=220)
    headline(canvas, title.split("\n"), line, 150, WHITE, (255, 255, 255, 236), shadow=True)
    edge = (0.0135 + 0.029) * 862
    peek(canvas, y, x + body_w * 0.76, 9, face, lambda: canvas.alpha_composite(phone, (x - pad, y - pad)), edge * 0.55)
    return canvas


def rising_shot(title, line, screen_name, face):
    """For screens filled only at the top (key points): a big iPhone rising out of a sea of
    clouds, the headline on the clouds."""
    width, y = 1120, 230
    phone, pad = device(app_screen(screen_name), width)
    body_w = phone.width - 2 * pad
    x = (SIZE[0] - body_w) // 2
    canvas = gradient(SIZE, SKY)
    light = layer(SIZE, WHITE)
    ImageDraw.Draw(light).ellipse([-300, -300, 700, 600], fill=(255, 255, 255, 46))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(160)))
    sparkle(canvas, (70, 120), 110, angle=-72)
    edge = (0.0135 + 0.029) * width
    peek(canvas, y, x + body_w * 0.76, 9, face, lambda: canvas.alpha_composite(phone, (x - pad, y - pad)), edge * 0.55)
    # Where the key points end: the lowest row with anything on it, plus the card's edge.
    pixels = np.array(Image.open(os.path.join(SHOTS, f"{screen_name}.png")).convert("L"))[:2700]
    last = np.nonzero((pixels < 235).any(axis=1))[0].max()
    content_end = y + edge + (last + 40) * width / SIZE[0]
    top = round(content_end + 40)
    cloud_bank(canvas, top)
    # A faint row of cloud tops along the bottom, and the headline between the rows.
    w, h = SIZE
    mask = Image.new("L", SIZE, 0)
    draw = ImageDraw.Draw(mask)
    for cx, r in [(-20, 150), (250, 175), (540, 150), (820, 185), (1100, 160), (1360, 150)]:
        draw.ellipse([cx - r, h - 120 - r, cx + r, h - 120 + r], fill=255)
    draw.rectangle([0, h - 120, w, h], fill=255)
    shade = Image.new("RGBA", SIZE, (120, 160, 220, 0))
    shade.putalpha(mask.filter(ImageFilter.GaussianBlur(18)).point(lambda a: a * 50 // 255))
    canvas.alpha_composite(shade, (0, -10))
    row = Image.new("RGBA", SIZE, (226, 237, 252, 0))
    row.putalpha(mask.filter(ImageFilter.GaussianBlur(1.5)))
    canvas.alpha_composite(row)
    front = top + 420
    middle = (front + h - 300) / 2
    headline(canvas, title.split("\n"), line, round(middle - 200), NAVY, GRAY + (255,), shadow=False, largest=132)
    return canvas


def slug(text):
    return "".join(c if c.isalnum() else "-" for c in text.split("\n")[0].lower()).strip("-")[:28].strip("-")


def make(page):
    (headline, line, face), shots = PAGES[page]
    folder = os.path.join(OUT, page)
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):
        if old.endswith(".png"):
            os.remove(os.path.join(folder, old))
    images = [(headline, hero_shot(headline, line, face))]
    images += [(spec[0], (rising_shot if spec[2].endswith("keyPoints") else phone_shot)(*spec)) for spec in shots]
    for n, (title, image) in enumerate(images, 1):
        path = os.path.join(folder, f"{n}-{slug(title)}.png")
        image.convert("RGB").save(path, optimize=True)
        print(os.path.relpath(path, ROOT))


def main():
    for page in sys.argv[1:] or list(PAGES):
        make(page)


if __name__ == "__main__":
    main()
