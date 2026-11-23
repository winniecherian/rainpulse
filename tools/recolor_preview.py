"""Preview of the on-device radar recolouring (same lookup table as RadarRecolor.swift)."""
import io, math, os, sys, requests
from PIL import Image

STOPS = [(0.0, (0, 200, 255)), (0.25, (0, 90, 255)), (0.45, (0, 200, 60)), (0.65, (255, 230, 0)),
         (0.8, (255, 140, 0)), (0.9, (230, 0, 0)), (1.0, (170, 0, 200))]
LO, HI = 8, 110

def lut(a):
    if a < LO:
        return (0, 0, 0, 0)
    t = min(1.0, (a - LO) / (HI - LO))
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            rgb = tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3))
            return rgb + (int(150 + 100 * t),)
    return STOPS[-1][1] + (250,)

def tile(lat, lon, z):
    n = 2 ** z
    r = math.radians(lat)
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)

key = os.environ["OWM_API_KEY"]
os.makedirs("preview", exist_ok=True)
for name, (la, lo), z in [("chennai", (13.08, 80.27), 5), ("india", (15, 80), 4), ("asia", (10, 100), 3)]:
    x, y = tile(la, lo, z)
    im = Image.open(io.BytesIO(requests.get(f"https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid={key}", timeout=30).content)).convert("RGBA")
    grey = Image.new("RGBA", im.size, (200, 200, 200, 255))
    before = Image.alpha_composite(grey, im)
    new = Image.new("RGBA", im.size)
    new.putdata([lut(p[3]) for p in im.getdata()])
    after = Image.alpha_composite(grey, new)
    out = Image.new("RGBA", (im.width * 2 + 10, im.height), (255, 255, 255, 255))
    out.paste(before, (0, 0)); out.paste(after, (im.width + 10, 0))
    out.save(f"preview/{name}.png")
    print(name, "saved")
