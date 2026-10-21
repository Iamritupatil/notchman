"""Notchman demo reel built from scratch: iPhone + screen recording + animated hand tapping in sync."""
import math, subprocess, sys
import cv2, numpy as np
from PIL import Image, ImageDraw, ImageFilter
import imageio_ffmpeg
sys.path.insert(0, '/home/user/notchman/scripts')
import store_screenshots as s

REC = sys.argv[1]; OUT = sys.argv[2]
W, H, FPS = 1080, 1920, 30
REC_DUR = 17.2; END = 2.6
SW = 700; SH = round(SW * 3118 / 1440)

# --- the iPhone frame, rendered once (screen area left clear) ---------------
rim, bezel, depth = 0.0135 * SW, 0.029 * SW, 0.0085 * SW
edge = rim + bezel; radius = 0.138 * SW
fw = math.ceil(SW + 2 * edge + 2 * depth); fh = math.ceil(SH + 2 * edge)
body = (depth, 0, depth + SW + 2 * edge, SH + 2 * edge)
gbox = (body[0] + edge, edge, body[2] - edge, body[3] - edge)
glass, _, _ = s.rounded_box(fw, fh, gbox, radius)
frame = s.side_buttons((fw, fh), body, rim, depth)
frame.alpha_composite(s.frame_ring((fw, fh), body, radius + edge, rim, bezel, glass))
sc = SW / 1440
ix0, iy0, ix1, iy1 = 472 * 2 * 0.5, 42, 846, 151   # unused precise; island drawn in screen coords below
screen_mask = Image.fromarray((s.coverage(glass - 1.0) * 255).astype(np.uint8), 'L')
shadow_src = Image.new('RGBA', (fw, fh), (0, 0, 0, 0)); shadow_src.paste((10, 30, 80, 255), (0, 0), Image.fromarray((s.coverage(s.rounded_box(fw, fh, body, radius + edge)[0]) * 255).astype(np.uint8)))
PX, PY = (W - fw) // 2, 250
SX, SY = PX + round(gbox[0]), PY + round(gbox[1])

bg = s.gradient((W, H), [(0, (31, 112, 230)), (0.55, (92, 160, 242)), (1, (196, 226, 255))])
light = s.layer((W, H), s.WHITE); ImageDraw.Draw(light).ellipse([-300, -300, 800, 600], fill=(255, 255, 255, 50))
bg.alpha_composite(light.filter(ImageFilter.GaussianBlur(160)))
s.sparkle(bg, (110, 1650), 80, angle=-72); s.sparkle(bg, (985, 1500), 50, rays=8); s.sparkle(bg, (960, 120), 45, rays=8)
soft = Image.new('RGBA', (W, H), (0, 0, 0, 0))
sh = shadow_src.copy(); sh.putalpha(sh.getchannel('A').point(lambda a: a * 90 // 255))
soft.alpha_composite(sh, (PX, PY + 40)); soft = soft.filter(ImageFilter.GaussianBlur(40))
bg.alpha_composite(soft)

# --- the hand -----------------------------------------------------------------
def make_hand():
    """A hand coming from the bottom right, index finger pointing up-left; fingertip at TIP."""
    S = 2; Wd, Hd = 1000 * S, 1300 * S
    im = Image.new('RGBA', (Wd, Hd), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    skin, dark, light = (240, 196, 164), (205, 150, 118), (250, 214, 188)
    dirx, diry = 0.50, 0.866          # from the fingertip toward the wrist
    nx_, ny_ = -diry, dirx            # across the finger
    tip = (110 * S, 100 * S); fw2 = 56 * S
    def cap(p, q, r, fill):
        d.line([p, q], fill=fill, width=int(2 * r))
        for c in (p, q): d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=fill)
    def at(f, side=0): return (tip[0] + dirx * f * S + nx_ * side * S, tip[1] + diry * f * S + ny_ * side * S)
    # palm (big rounded shape) and wrist
    palm = at(640, 40)
    cap(palm, at(1300, 60), 230 * S, dark); cap(palm, at(1300, 60), 224 * S, skin)
    # curled fingers along the palm's top edge
    for j in range(3):
        k = at(470 + j * 30, -95 - j * 95)
        d.ellipse([k[0] - 92 * S, k[1] - 92 * S, k[0] + 92 * S, k[1] + 92 * S], fill=dark)
        d.ellipse([k[0] - 87 * S, k[1] - 87 * S, k[0] + 87 * S, k[1] + 87 * S], fill=skin)
    # thumb along the other side
    t0, t1 = at(700, 190), at(470, 150)
    cap(t0, t1, 64 * S, dark); cap(t0, t1, 59 * S, skin)
    # index finger
    p0 = at(fw2 / S); p1 = at(560)
    cap(p0, p1, fw2 + 4 * S, dark); cap(p0, p1, fw2, skin)
    cap(at(fw2 / S + 30, -18), at(520, -18), 14 * S, light)   # highlight
    # nail
    nc = at(fw2 / S + 28)
    nl = Image.new('RGBA', im.size, (0, 0, 0, 0)); ImageDraw.Draw(nl).ellipse([nc[0] - 32 * S, nc[1] - 44 * S, nc[0] + 32 * S, nc[1] + 44 * S], fill=(252, 226, 212, 255))
    angle = math.degrees(math.atan2(diry, dirx)) - 90
    im.alpha_composite(nl.rotate(-angle, center=nc))
    for f in (230, 360):
        c = at(f)
        d.line([at(f, -40), at(f, 40)], fill=dark, width=3 * S)
    im = im.resize((Wd // S, Hd // S), Image.LANCZOS)
    return im, (tip[0] // S, tip[1] // S)
HAND, TIP = make_hand()
HAND = HAND.resize((int(HAND.width*0.78), int(HAND.height*0.78)), Image.LANCZOS); TIP = (int(TIP[0]*0.78), int(TIP[1]*0.78))
HAND_SHADOW = Image.new('RGBA', HAND.size, (10, 30, 80, 0)); HAND_SHADOW.putalpha(HAND.getchannel('A').point(lambda a: a * 70 // 255))
HAND_SHADOW = HAND_SHADOW.filter(ImageFilter.GaussianBlur(14))

# --- what the finger does (times in the recording; positions as screen fractions)
TAPS = [  # (down, up, x, y, kind)
    (0.15, 0.75, 0.45, 0.35, 'hold'),      # long-press the message
    (1.95, 2.10, 0.31, 0.61, 'tap'),       # Copy
    (3.15, 3.80, 0.50, 0.03, 'hold'),      # hold the Shiba in the Dynamic Island
    (4.08, 4.22, 0.29, 0.092, 'tap'),      # TL;DR
    (10.55, 10.70, 0.885, 0.103, 'tap'),    # ...
    (11.70, 11.85, 0.52, 0.118, 'tap'),    # Speed
    (12.75, 12.90, 0.43, 0.254, 'tap'),    # 1x
    (13.75, 14.05, (0.5, 0.5), (0.985, 0.62), 'swipe'),  # home
    (15.15, 15.50, (0.80, 0.20), (0.50, 0.50), 'swipe'),
    (15.90, 16.30, (0.80, 0.20), (0.50, 0.50), 'swipe'),
    (16.60, 17.00, (0.80, 0.20), (0.50, 0.50), 'swipe'),
]
REST = (1.25, 1.15)   # off the phone, bottom right (fractions; >1 = off screen)

def to_px(fx, fy): return SX + fx * SW, SY + fy * SH
def ease(t): return t * t * (3 - 2 * t)

def finger_state(t):
    """(x, y, pressed 0..1, visible) at recording time t."""
    keys = []  # (time, x, y, pressed)
    prev_end = -1; prev_pos = REST
    for down, up, x, y, kind in TAPS:
        if kind == 'swipe':
            start = (x[0], y[0]); end = (x[1], y[1])
        else:
            start = end = (x, y)
        approach = max(prev_end + 0.15, down - 0.45)
        keys.append((approach, start[0], start[1], 0.0, 'move'))
        keys.append((down, start[0], start[1], 1.0, kind))
        keys.append((up, end[0], end[1], 1.0 if kind != 'tap' else 1.0, kind))
        keys.append((up + 0.12, end[0], end[1], 0.0, 'lift'))
        prev_end = up + 0.12
    # gaps longer than 1.6 s: the hand rests away
    for i in range(len(keys) - 1):
        t0, x0, y0, p0, _ = keys[i]; t1, x1, y1, p1, k1 = keys[i + 1]
        if t0 <= t <= t1:
            gap = t1 - t0
            u = (t - t0) / max(gap, 1e-6)
            if gap > 1.6 and p0 == 0 and p1 == 0:
                # go away and come back
                if u < 0.3: v = ease(u / 0.3); return (x0 + (REST[0] - x0) * v, y0 + (REST[1] - y0) * v, 0)
                if u > 0.7: v = ease((u - 0.7) / 0.3); return (REST[0] + (x1 - REST[0]) * v, REST[1] + (y1 - REST[1]) * v, 0)
                return (*REST, 0)
            v = ease(u) if k1 in ('move', 'lift', 'tap', 'hold') else u
            return (x0 + (x1 - x0) * v, y0 + (y1 - y0) * v, p0 + (p1 - p0) * (u if k1 == 'lift' else (1 if p1 >= p0 and t >= t1 - 0.001 else v)))
    if t < keys[0][0]:
        u = min(1, max(0, t / max(keys[0][0], 0.01)))
        return (REST[0] + (keys[0][1] - REST[0]) * ease(u), REST[1] + (keys[0][2] - REST[1]) * ease(u), 0)
    last = keys[-1]; u = min(1, (t - last[0]) / 0.5)
    return (last[1] + (REST[0] - last[1]) * ease(u), last[2] + (REST[1] - last[2]) * ease(u), 0)

CAPS = [(0, 2.4, "this post was WAY too long to read"),
        (2.4, 4.3, "copy it, hold the Shiba, tap TL;DR"),
        (4.3, 7.6, "Notchman finds what matters"),
        (7.6, 13.6, "and reads me the TL;DR out loud"),
        (13.6, 99, "no more walls of text")]
CF = s.font('InterDisplay-Bold.ttf', 50)

def caption(img, text):
    d = ImageDraw.Draw(img); tw = CF.getlength(text)
    box = s.layer((W, H)); bd = ImageDraw.Draw(box)
    bd.rounded_rectangle([W / 2 - tw / 2 - 34, 98, W / 2 + tw / 2 + 34, 196], radius=30, fill=(255, 255, 255, 255))
    lifted, pad = s.shadowed(box.crop((0, 0, W, 260)), 16, (0, 8), 60)
    img.alpha_composite(lifted, (-pad, -pad))
    d.text((W / 2, 147), text, font=CF, fill=(14, 22, 44), anchor='mm')

def end_card(u):
    img = bg.copy()
    headimg = s.head('happy', 16)
    y = 520 - int(30 * (1 - ease(min(1, u * 2))))
    img.alpha_composite(headimg, ((W - headimg.width) // 2, y))
    d = ImageDraw.Draw(img)
    d.text((W / 2, y + headimg.height + 90), 'Notchman', font=s.font('InterDisplay-ExtraBold.ttf', 110), fill=s.WHITE, anchor='mm')
    d.text((W / 2, y + headimg.height + 190), 'Copy anything. Hear what matters.', font=s.font('Inter-SemiBold.ttf', 46), fill=s.WHITE, anchor='mm')
    f = s.font('Inter-SemiBold.ttf', 40); t = 'Free on iPhone, Mac & Windows'
    tw = f.getlength(t)
    d.rounded_rectangle([W / 2 - tw / 2 - 40, y + headimg.height + 270, W / 2 + tw / 2 + 40, y + headimg.height + 360], radius=45, fill=(255, 255, 255))
    d.text((W / 2, y + headimg.height + 315), t, font=f, fill=(20, 90, 210), anchor='mm')
    return img

ff = imageio_ffmpeg.get_ffmpeg_exe()
p = subprocess.Popen([ff, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                      '-i', REC, '-map', '0:v', '-map', '1:a', '-af', f'apad=whole_dur={REC_DUR + END}', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18',
                      '-preset', 'medium', '-c:a', 'aac', '-b:a', '160k', '-t', str(REC_DUR + END), '-movflags', '+faststart', OUT], stdin=subprocess.PIPE)
cap = cv2.VideoCapture(REC); ri = -1; rf = None
total = int((REC_DUR + END) * FPS)
for i in range(total):
    t = i / FPS
    if t < REC_DUR:
        want = min(int(round(t * 60)), 1031)
        while ri < want:
            ok, fr = cap.read()
            if not ok: break
            rf = fr; ri += 1
        scr = Image.fromarray(cv2.cvtColor(cv2.resize(rf, (SW, SH), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB)).convert('RGBA')
        img = bg.copy()
        phone = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
        phone.paste(scr, (round(gbox[0]), round(gbox[1])))
        phone.putalpha(Image.fromarray(np.maximum(np.array(phone.getchannel('A')) * (np.array(screen_mask) > 0), 0).astype(np.uint8)))
        phone.alpha_composite(frame)
        bob = int(round(6 * math.sin(t * 1.3)))
        img.alpha_composite(phone, (PX, PY + bob))
        fx, fy, pr = finger_state(t)
        x, y = to_px(fx, fy); y += bob
        if pr > 0.05:  # touch ripple
            rp = s.layer((W, H), s.WHITE); rd = ImageDraw.Draw(rp)
            r = 34 + 10 * pr
            rd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(110 * pr)))
            img.alpha_composite(rp.filter(ImageFilter.GaussianBlur(3)))
        lift = 1 - pr
        sx, sy = int(x - TIP[0] + 18 + 22 * lift), int(y - TIP[1] + 26 + 30 * lift)
        img.alpha_composite(HAND_SHADOW, (sx, sy)) if -HAND.width < sx < W and -HAND.height < sy < H else None
        hx, hy = int(x - TIP[0] - 6 * lift), int(y - TIP[1] - 8 * lift)
        if -HAND.width < hx < W and -HAND.height < hy < H:
            img.alpha_composite(HAND, (hx, hy)) if hx >= 0 and hy >= 0 else img.paste(HAND, (hx, hy), HAND)
        caption(img, next(c[2] for c in CAPS if c[0] <= t < c[1]))
    else:
        img = end_card((t - REC_DUR) / END)
    p.stdin.write(np.asarray(img.convert('RGB')).tobytes())
p.stdin.close(); p.wait(); print('wrote', OUT)
