#!/usr/bin/env python3
"""The Shiba: pixel art drawn here, cell by cell, so it can move.

The apps show just its head (blinking, a listening ear, thinking, talking,
happy), written to:
  - Notchman/Resources/Assets.xcassets/ShibaHead<Frame>.imageset  (iPhone app)
  - desktop/assets/shiba-head-sprites.png  (Windows/Mac: the frames side by side)
  - design/art/shiba-head.png              (a large preview)
The full body (head, body, tail, a waving paw) is kept for artwork:
  - desktop/assets/shiba-sprites.png, design/art/shiba-body.png

Run: python3 scripts/shiba_sprites.py   (needs Pillow)

Cell codes: k outline (navy), b fur (blue), d fur shade, l highlight,
w white, g white shade, p pink, P inside of the mouth, . transparent.
"""
import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

PAL = {
 'k': (11,26,66,255), 'b': (74,168,248,255), 'd': (52,138,222,255), 'l': (143,211,250,255),
 'w': (248,248,248,255), 'g': (218,231,244,255), 'p': (242,124,140,255), 'P': (150,40,70,255), '.': (0,0,0,0),
}
W, H = 34, 30
def mirror(half): return [r + r[::-1] for r in half]

HEAD = mirror([
 "...kk.....",
 "..kbbkk...",
 "..kbwbbk..",
 "..kbwpbbkk",
 "..kbwbbbbb",
 "..kbbbbbbb",
 "..kbbblwwb",
 ".kbbbbkkwl",
 ".kbbbwkkww",
 "kbbbwwwwwk",
 "kkbwwwwkww",
 "..kwwwwlkk",
 "...kkwwwkp",
 "....kkkwwp",
 "......kkkk",
])
# eyes: rows 7-8, cols 6-7 and 12-13 of the head
EYES = {
 'open':  {},
 'closed':{(7,6):'b',(7,7):'w',(8,6):'k',(8,7):'k'},
 'up':    {(6,6):'k',(6,7):'k',(7,6):'k',(7,7):'k',(8,6):'b',(8,7):'w'},
}
def eyes(kind):
    cells = {}
    for (r,c),v in EYES[kind].items():
        cells[(r,c)] = v
        cells[(r,19-c)] = v
    return cells
MOUTH = {
 'tongue': {},
 'open': {(11,8):'k',(11,9):'P',(11,10):'P',(11,11):'k',(12,9):'p',(12,10):'p',(13,9):'p',(13,10):'p'},
 'smile': {(12,9):'w',(12,10):'w',(13,9):'w',(13,10):'w',(12,8):'w',(12,11):'w',(11,8):'k',(11,11):'k',(11,9):'k',(11,10):'k'},
}

BODY = mirror([
 "..........kkkkkk.",
 ".........kdbbbbbb",
 "........kdbbbbwww",
 "........kdbbbwwww",
 ".......kdbbbwwwww",
 ".......kdbbbwwwww",
 ".......kdbbbbwwww",
 "......kdbbbbbwwww",
 "......kdbkbbbbwww",
 ".....kdbbkbbbbkww",
 ".....kdbbkbbbbkgw",
 "....kdbbbkwwwwkgg",
 "....kdbbbkwwwwkgg",
 "....kdbbkwwwwwwkg",
 "....kdbbkwkwkwwkg",
 ".....kkkkkkkkkkkk",
])
# The viewer's-left front leg lifted (for waving): the leg area becomes chest.
LEG_UP = {}
for r, row in enumerate([
 "......kdbkbbbwwww",
 ".....kdbbkbbwwwww",
 ".....kdbbkbbwwwgw",
 "....kdbbbkbbwwwgg",
 "....kdbbbkbbbwwgg",
 "....kdbbbbkbbbwgg",
 "....kdbbbbbkkkkgg",
]):
    for c, v in enumerate(row): LEG_UP[(21 + r, c)] = v
PAW = [".kkkk.",
       "kwpwpk",
       "kwwwwk",
       "kwppwk",
       ".kwwk."]
FOREARM = ["..kbbk..",
           "..kbbbk.",
           "...kbbk.",
           "...kbbbk",
           "....kbbk"]
def arm_cells(kind):
    rows = {}
    dx, dy = (0, 0) if kind == 'wave1' else (-1, -1)
    for j, row in enumerate(PAW):
        for i, v in enumerate(row): rows[(j + dy, i + 1 + dx)] = v
    for j, row in enumerate(FOREARM):
        for i, v in enumerate(row): rows[(5 + j, i)] = v
    return rows
TAIL = {
 'a': ["..kkkk..",
       ".kbbbbk.",
       "kbbwwbbk",
       "kbwddwbk",
       "kbwddwbk",
       "kbbwwbbk",
       ".kbbbbk.",
       "..kbbk..",
       "..kbbk.."],
 'b': ["...kkkk.",
       "..kbbbbk",
       ".kbbwwbbk",
       ".kbwddwbk",
       ".kbwddwbk",
       ".kbbwwbbk",
       "..kbbbbk.",
       "..kbbk...",
       "..kbbk..."],
}
def frame(eye='open', mouth='tongue', tail='a', arm=None, bob=0):
    g = [['.']*W for _ in range(H)]
    def put(r, c, v):
        if v != '.' and 0 <= r < H and 0 <= c < W: g[r][c] = v
    def stamp(rows, x, y):
        for j, row in enumerate(rows):
            for i, v in enumerate(row): put(y+j, x+i, v)
    stamp(TAIL[tail], 23, 13)
    stamp(BODY, 0, 13)
    if arm:
        for (r,c),v in LEG_UP.items(): g[r][c] = v
    hx, hy = 7, 0 + bob
    stamp(HEAD, hx, hy)
    for (r,c),v in eyes(eye).items(): put(hy+r, hx+c, v)
    for (r,c),v in MOUTH[mouth].items(): put(hy+r, hx+c, v)
    if arm:
        for (r, c), v in arm_cells(arm).items(): put(9 + r, 1 + c, v)
    return g

def render(g):
    img = Image.new('RGBA', (W, H))
    for j in range(H):
        for i in range(W): img.putpixel((i, j), PAL[g[j][i]])
    return img

FRAMES = {
 'idle': frame(), 'wag': frame(tail='b'), 'blink': frame(eye='closed'),
 'wave1': frame(eye='closed', mouth='open', arm='wave1'), 'wave2': frame(eye='closed', mouth='open', arm='wave2', tail='b'),
 'talk1': frame(mouth='open'), 'talk2': frame(mouth='smile', tail='b'),
 'think': frame(eye='up', mouth='smile'),
}

# The order the desktop sprite sheet uses (keep in sync with
# desktop/src/ui/shiba.js).
ORDER = ["idle", "wag", "blink", "wave1", "wave2", "talk1", "talk2", "think"]


# --- Just the head: the small floating Shiba on Windows and Mac -------------
# 20x17 cells (the head, with two rows above it for a perked ear). It listens
# with one ear up (which twitches), looks up while thinking, talks, and is
# happy (eyes closed, both ears up) when it says hello.
HW, HH = 20, 17


# A perked ear (the viewer's right), drawn over canvas rows 0-3, columns 12-18:
# taller and pointier than the other. 1 is the halfway pose for a twitch.
PERKED = {
    2: ["....k..",
        "...kbk.",
        "..kbbk.",
        ".kbwbk."],
    1: [".......",
        "...kk..",
        "..kbbk.",
        ".kbwbk."],
}


def head(eye='open', mouth='tongue', perk=0, both=False, shift=0):
    g = [['.'] * HW for _ in range(HH)]
    rows = [list(r) for r in HEAD]
    for (r, c), v in eyes(eye).items(): rows[r][c] = v
    for (r, c), v in MOUTH[mouth].items(): rows[r][c] = v
    for j, row in enumerate(rows):
        for i, v in enumerate(row):
            if v != '.' and 0 <= i + shift < HW: g[2 + j][i + shift] = v

    def ear(pose, mirrored):
        for j, row in enumerate(PERKED[pose]):
            for k, v in enumerate(row):
                c = 12 + k
                if mirrored: c = HW - 1 - c
                c += shift
                if 0 <= c < HW and (v != '.' or j < 3): g[j][c] = v

    if perk: ear(perk, False)
    if both: ear(1, True)
    return g


HEAD_FRAMES = {
    'idle': head(), 'blink': head(eye='closed'),
    'listen1': head(perk=2), 'listen2': head(perk=1),
    'think1': head(eye='up', mouth='smile'), 'think2': head(eye='up', mouth='smile', shift=1),
    'talk1': head(mouth='open'), 'talk2': head(mouth='smile'),
    'happy': head(eye='closed', mouth='open', perk=1, both=True),
}
# The order of desktop/assets/shiba-head-sprites.png (keep in sync with shiba.js).
HEAD_ORDER = ["idle", "blink", "listen1", "listen2", "think1", "think2", "talk1", "talk2", "happy"]


def render_head(g):
    img = Image.new('RGBA', (HW, HH))
    for j in range(HH):
        for i in range(HW): img.putpixel((i, j), PAL[g[j][i]])
    return img


def heads():
    images = [render_head(HEAD_FRAMES[name]) for name in HEAD_ORDER]
    # iPhone: one image set per frame (ShibaHeadIdle, ShibaHeadListen1, ...).
    for name, img in zip(HEAD_ORDER, images):
        folder = os.path.join(ROOT, "Notchman/Resources/Assets.xcassets", f"ShibaHead{name[0].upper()}{name[1:]}.imageset")
        os.makedirs(folder, exist_ok=True)
        img.save(os.path.join(folder, "Shiba.png"))
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": "Shiba.png", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)
            f.write("\n")
    sheet = Image.new("RGBA", (HW * len(images), HH))
    for n, img in enumerate(images): sheet.alpha_composite(img, (n * HW, 0))
    sheet.save(os.path.join(ROOT, "desktop/assets/shiba-head-sprites.png"))
    s = 10
    preview = Image.new("RGBA", ((HW * s + 16) * len(images) + 16, HH * s + 32), (205, 226, 247, 255))
    for n, img in enumerate(images):
        preview.alpha_composite(img.resize((HW * s, HH * s), Image.NEAREST), (16 + n * (HW * s + 16), 16))
    preview.save(os.path.join(ROOT, "design/art/shiba-head.png"))
    print(f"{len(images)} head frames, {HW}x{HH} cells each")


def main():
    heads()
    images = {name: render(FRAMES[name]) for name in ORDER}

    # Desktop: the frames side by side.
    sheet = Image.new("RGBA", (W * len(ORDER), H))
    for n, name in enumerate(ORDER):
        sheet.alpha_composite(images[name], (n * W, 0))
    sheet.save(os.path.join(ROOT, "desktop/assets/shiba-sprites.png"))

    # A large preview.
    s = 8
    preview = Image.new("RGBA", ((W * s + 16) * 4 + 16, (H * s + 16) * 2 + 16), (205, 226, 247, 255))
    for n, name in enumerate(ORDER):
        preview.alpha_composite(images[name].resize((W * s, H * s), Image.NEAREST),
                                (16 + (n % 4) * (W * s + 16), 16 + (n // 4) * (H * s + 16)))
    preview.save(os.path.join(ROOT, "design/art/shiba-body.png"))
    print(f"{len(ORDER)} frames, {W}x{H} cells each")


if __name__ == "__main__":
    main()
