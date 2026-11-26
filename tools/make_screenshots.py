"""Captioned App Store screenshots (1290x2796, 6.9"/6.7" slot) from raw UI-test screenshots.
usage: python3 make_screenshots.py <raw_dir> <out_dir>  (raw files named 01-Radar.png etc.)"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1290, 2796
BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
SEMI = "/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf"
SHOTS = [
    ("02-Forecast", "Know exactly\nwhen it rains", "The Rain Clock shows the next 2 hours", [(10, 40, 90), (40, 90, 170)]),
    ("01-Radar", "Live rain map,\nbold and clear", "Rain forecast animation up to 48 hours", [(5, 10, 30), (25, 40, 90)]),
    ("01b-WindFlow-Cyclone", "Track cyclones\nand wind", "Storm paths, forecast cones and alerts", [(30, 12, 50), (90, 30, 90)]),
    ("03-KeyConditions", "Rain, snow, wind\nand air quality", "Everything that matters, nothing that doesn't", [(8, 45, 60), (20, 110, 120)]),
    ("05b-Privacy", "Private by design", "No account, no ads, no tracking. Face ID lock", [(15, 15, 25), (50, 50, 75)]),
]

def gradient(c1, c2):
    g = Image.new("RGB", (W, H), c1)
    d = ImageDraw.Draw(g)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g

def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], r, fill=255)
    out = im.convert("RGBA"); out.putalpha(m); return out

def make(raw, title, sub, colors, out):
    bg = gradient(*colors).convert("RGBA")
    d = ImageDraw.Draw(bg)
    tf, sf = ImageFont.truetype(BOLD, 112), ImageFont.truetype(SEMI, 50)
    y = 170
    for line in title.split("\n"):
        w = d.textlength(line, font=tf)
        d.text(((W - w) / 2, y), line, font=tf, fill="white"); y += 128
    w = d.textlength(sub, font=sf)
    d.text(((W - w) / 2, y + 22), sub, font=sf, fill=(220, 230, 255))
    shot = Image.open(raw).convert("RGB")
    sw = 1030; sh = int(shot.height * sw / shot.width)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 70)
    top = y + 150
    shadow = Image.new("RGBA", (sw + 120, sh + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([60, 60, sw + 60, sh + 60], 70, fill=(0, 0, 0, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    bg.alpha_composite(shadow, ((W - sw) // 2 - 60, top - 40))
    # thin bezel
    bezel = Image.new("RGBA", (sw + 24, sh + 24), (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle([0, 0, sw + 23, sh + 23], 82, fill=(18, 18, 22, 255))
    bg.alpha_composite(bezel, ((W - sw) // 2 - 12, top - 12))
    bg.alpha_composite(shot, ((W - sw) // 2, top))
    bg.convert("RGB").save(out, "PNG")

if __name__ == "__main__":
    raw_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for i, (name, title, sub, colors) in enumerate(SHOTS, 1):
        src = os.path.join(raw_dir, name + ".png")
        if os.path.exists(src):
            make(src, title, sub, colors, os.path.join(out_dir, f"{i:02d}-{name}.png"))
            print("made", i, name)
