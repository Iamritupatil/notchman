#!/usr/bin/env python3
"""The full-body Shiba: pixel art drawn here, cell by cell, so it can move.

Every frame is built from parts (head, body, tail, a waving paw, eyes and
mouth) in the brand Shiba's colours, and written to:
  - Notchman/Resources/Assets.xcassets/Shiba<Frame>.imageset  (iPhone app)
  - desktop/assets/shiba-sprites.png   (Windows/Mac: the frames side by side)
  - design/art/shiba-body.png          (a large preview of every frame)

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


def main():
    images = {name: render(FRAMES[name]) for name in ORDER}

    # iPhone: one image set per frame, drawn at 1x and scaled up without smoothing.
    for name, img in images.items():
        folder = os.path.join(ROOT, "Notchman/Resources/Assets.xcassets", f"Shiba{name[0].upper()}{name[1:]}.imageset")
        os.makedirs(folder, exist_ok=True)
        img.save(os.path.join(folder, "Shiba.png"))
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": "Shiba.png", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)
            f.write("\n")

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
