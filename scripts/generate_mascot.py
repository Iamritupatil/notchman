#!/usr/bin/env python3
"""Generates the pixel-art Shiba mascot sprites and the app icon.

Sprites are authored as character grids (left half, mirrored) so they stay
editable. Each cell is one pixel; SwiftUI scales them with interpolation off.

Usage: python3 scripts/generate_mascot.py   (requires Pillow)
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Notchman/Resources/Assets.xcassets"

PALETTE = {
    ".": (0, 0, 0, 0),
    "K": (58, 32, 16, 255),     # outline
    "O": (240, 158, 48, 255),   # orange fur
    "D": (214, 124, 36, 255),   # fur shade
    "C": (255, 240, 214, 255),  # cream mask
    "P": (247, 160, 170, 255),  # inner ear
    "N": (24, 20, 20, 255),     # nose
    "M": (110, 30, 36, 255),    # mouth
    "T": (240, 82, 110, 255),   # tongue
    "S": (232, 214, 186, 255),  # cream shade (chest)
    "G": (250, 190, 40, 255),   # collar tag (gold)
    "R": (40, 36, 36, 255),     # collar
}

# Traced from the Notchman design mockups (pitch-detected, then hand-cleaned).
# Left half of a 32-wide sprite; mirrored at render time.
HEAD_LEFT = [
    "....KKK.........",
    "...KOOOK........",
    "...KOPOOK.......",
    "...KOPPOOK......",
    "...KOPPPOOK.....",
    "...KOPPPOOOKKKKK",
    "...KOPPDOOOOOOOO",
    "...KOPDOOOOOOOOO",
    "..KDODOOOOCOOOOO",
    "..KDDOOOOOCCOOOO",
    "..KDOOOOOOOOOOOO",
    "..KDOOOOKKKOOOOO",
    "..KDOOOKOOOKOOCC",
    "..KDOOOOOOOOCCNN",
    ".KDDOOOOOOOCCNNN",
    ".KDDOCCCOCCCCCNN",
    ".KDCCCCCCCCCCCCK",
    ".KOCCCCCCCKCCCCK",
    ".KCCCCCCCCCKKKKK",
    ".KCCCCCCCCCKMMMM",
    ".KCCCCCCCCCCKMTT",
    "..KCCCCCCCCCCKTT",
    "..KCCCCCCCCCCCKK",
    "...KCCCCCCCCCCCC",
    "....KSSSSSSSSSSS",
    ".....KSSSSSSSSSS",
    ".....KSSSSSSSSSS",
    "......KKKKKKKKKK",
]

PAW = [
    ".KKKKKK.",
    "KOOOOOOK",
    "KODOOODK",
    "KCCCCCCK",
    "KCKCCKCK",
    "KCKCCKCK",
    ".KKKKKK.",
]

COLLAR_LEFT = [
    "....KRRRRRRRRRRR",
    ".....KRRRRRRRRRG",
    "..............KG",
]


def mirror(rows):
    return [row + row[::-1] for row in rows]


def overlay(grid, sprite, top, left):
    grid = [list(r) for r in grid]
    for y, row in enumerate(sprite):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            yy, xx = top + y, left + x
            while yy >= len(grid):
                grid.append(["."] * len(grid[0]))
            grid[yy][xx] = ch
    return ["".join(r) for r in grid]


def head():
    return mirror(HEAD_LEFT)


def head_with_paws():
    grid = head()
    grid = overlay(grid, PAW, 21, 0)
    grid = overlay(grid, PAW, 21, 24)
    return grid


def head_with_collar():
    grid = head()[:24]
    grid = overlay(grid, mirror(COLLAR_LEFT), 23, 0)
    return grid


def render(grid, scale=1, background=None, canvas=None, offset=(0, 0)):
    h, w = len(grid), len(grid[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            img.putpixel((x, y), PALETTE[ch])
    img = img.resize((w * scale, h * scale), Image.NEAREST)
    if canvas:
        base = Image.new("RGBA", canvas, background or (0, 0, 0, 0))
        base.alpha_composite(img, offset)
        return base
    return img


def imageset(name, image, catalog=ASSETS):
    if not (catalog / "Contents.json").exists():
        catalog.mkdir(parents=True, exist_ok=True)
        (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    folder = catalog / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        # Pixel art: never smooth when scaling.
        "properties": {"preserves-vector-representation": False},
    }, indent=2))


def app_icon():
    """The Shiba peeking over the top of a phone, notch and all, on a night sky."""
    cells, cell = 64, 16
    bg, cloud, amber = (12, 12, 14), (34, 34, 38), (250, 170, 30)
    bezel, screen, notch, camera = (120, 120, 126), (22, 22, 25), (8, 8, 10), (40, 90, 210)
    g = [[bg] * cells for _ in range(cells)]

    def put(x, y, c):
        if 0 <= x < cells and 0 <= y < cells:
            g[y][x] = c

    # Pixel clouds.
    for cx, cy, w in [(2, 8, 10), (46, 5, 14), (0, 24, 7), (56, 20, 8), (1, 38, 8), (54, 34, 10)]:
        for dy, (off, span) in enumerate([(3, w - 6), (1, w - 2), (0, w)]):
            for x in range(cx + off, cx + off + span):
                put(x, cy + dy, cloud)

    # Sparkles: plus signs and dots.
    for x, y in [(21, 9), (55, 12), (6, 16), (12, 36), (51, 37)]:
        for dx, dy in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
            put(x + dx, y + dy, amber)
        put(x, y, (255, 240, 200))
    for x, y in [(16, 5), (24, 3), (40, 10), (32, 11), (13, 21), (51, 18), (8, 37), (52, 31)]:
        put(x, y, amber)

    # Excitement zaps either side of the head.
    # Each zap is a small pixel zigzag; right-side zaps mirror the left.
    zig = [(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (3, 2), (1, 2), (0, 2)]
    for sx, sy in [(8, 19), (5, 28)]:
        for dx, dy in zig[:6]:
            put(sx + dx, sy + dy, amber)
            put(63 - (sx + dx), sy + dy, amber)

    # Shiba, peeking up from behind the phone.
    sprite = head_with_paws()
    top, left = 44 - 25, (cells - 32) // 2
    for y, row in enumerate(sprite):
        for x, ch in enumerate(row):
            if ch != ".":
                put(left + x, top + y, PALETTE[ch][:3])

    # Phone: bezel with stepped corners, dark screen and notch.
    edge = 44
    for y in range(edge, cells):
        for x in range(2, 62):
            put(x, y, screen)
    for x in range(5, 59):
        put(x, edge, bezel)
    for i, (dx, dy) in enumerate([(4, 1), (3, 2), (3, 3), (2, 4)]):
        put(dx, edge + dy, bezel)
        put(63 - dx, edge + dy, bezel)
    for y in range(edge + 4, cells):
        put(2, y, bezel)
        put(61, y, bezel)
    for x in range(0, 64):
        for y in range(edge + 1, edge + 5):
            if x in (0, 1, 62, 63) or (y - edge) < {0: 9, 1: 9, 62: 9, 63: 9}.get(x, 0):
                put(x, y, bg)
    for y in range(edge + 1, edge + 8):
        for x in range(19, 45):
            put(x, y, notch)
    put(37, edge + 3, camera)
    put(37, edge + 2, (70, 130, 240))

    # Paws rest on top of the bezel.
    for y, row in enumerate(sprite):
        for x, ch in enumerate(row):
            if ch != "." and (x < 8 or x >= 24) and y >= 21 and top + y >= 44:
                put(left + x, top + y, PALETTE[ch][:3])

    img = Image.new("RGB", (cells, cells))
    for y in range(cells):
        for x in range(cells):
            img.putpixel((x, y), g[y][x])
    return img.resize((cells * cell, cells * cell), Image.NEAREST)


def main():
    imageset("ShibaHead", render(head()[:24]))
    imageset("ShibaPaws", render(head_with_paws()))
    imageset("ShibaCollar", render(head_with_collar()))
    # Extensions are separate bundles and need their own copies.
    imageset("ShibaPaws", render(head_with_paws()), ROOT / "Extensions/ShareExtension/Assets.xcassets")
    imageset("ShibaHead", render(head()[:24]), ROOT / "Extensions/LiveActivityWidget/Assets.xcassets")

    folder = ASSETS / "AppIcon.appiconset"
    for old in folder.glob("*.png"):
        old.unlink()
    app_icon().save(folder / "AppIcon-1024.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    sprite = head_with_paws()

    # Safari extension icons.
    safari = ROOT / "Extensions/SafariExtension/Resources/images"
    for size in (48, 64, 96, 128, 256, 512):
        s = max(1, size // 34)
        img = render(sprite, s, background=(14, 14, 16, 255), canvas=(size, size),
                     offset=((size - 32 * s) // 2, (size - len(sprite) * s) // 2))
        img.save(safari / f"icon-{size}.png")
    for size in (16, 19, 32, 38, 48, 72):
        img = render(head(), 1).resize((size, size * 24 // 32), Image.NEAREST)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.alpha_composite(img, (0, (size - img.height) // 2))
        canvas.save(safari / f"toolbar-icon-{size}.png")

    # Preview sheet for humans.
    preview = Image.new("RGBA", (32 * 12 * 3 + 80, 29 * 12 + 40), (14, 14, 16, 255))
    for i, grid in enumerate([head(), head_with_paws(), head_with_collar()]):
        preview.alpha_composite(render(grid, 12), (20 + i * (32 * 12 + 20), 20))
    preview.save(ROOT / "docs/mascot-preview.png")


if __name__ == "__main__":
    main()
