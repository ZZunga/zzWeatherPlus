"""
preview.py - zzWeatherPlus 레이아웃 미리보기 (실제 비트맵 폰트로 렌더)

    python tools/preview.py            -> tools/preview.png

source/zzWeatherPlusView.mc 의 패널 배치 로직을 그대로 옮긴 것.
View 쪽 레이아웃을 고치면 여기도 같이 맞춘다. (Pillow 필요: pip install pillow)
"""
import math, os, re, sys, datetime as dt
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "resources", "fonts")

TW_PX = [16, 20, 24, 30, 38, 48, 60, 76, 96, 120, 29, 34, 50, 58]
TW_ADV = [9, 11, 13, 17, 21, 27, 34, 43, 54, 67, 16, 19, 28, 32]
TW_CAP = [12, 15, 18, 22, 27, 34, 42, 53, 67, 83, 20, 24, 36, 41]
TW_FILE = ["tw-%d" % p for p in TW_PX[:10]] + ["tw-s20", "tw-s24", "tw-s36", "tw-s41"]
SW = [246]
WX_PX = [20, 26, 32, 40, 52, 64, 80, 100]
WX_ADV = [32, 41, 51, 64, 83, 102, 128, 159]
WX_CAP = [29, 38, 46, 57, 74, 91, 114, 142]

LIGHT = dict(bg=(255, 255, 255), fg=(0, 0, 0), dim=(85, 85, 85), line=(170, 170, 170),
             accent=(255, 85, 0), red=(170, 0, 0), blue=(0, 0, 170), gray=(85, 85, 85),
             moon_dark=(170, 170, 170))
DARK = dict(bg=(0, 0, 0), fg=(255, 255, 255), dim=(170, 170, 170), line=(85, 85, 85),
            accent=(255, 255, 0), red=(255, 0, 0), blue=(0, 85, 255), gray=(170, 170, 170),
            moon_dark=(85, 85, 85))

NAV_X = [0.0, 0.848, 0.0, -0.848]
NAV_Y = [-1.0, 1.0, 0.398, 1.0]


class BmFont:
    def __init__(self, name):
        self.chars = {}
        with open(os.path.join(FONTS, name + ".fnt")) as f:
            for line in f:
                if line.startswith("char "):
                    kv = dict(re.findall(r"(\w+)=(-?\d+)", line))
                    self.chars[int(kv["id"])] = {k: int(v) for k, v in kv.items()}
        self.sheet = Image.open(os.path.join(FONTS, name + "_0.png")).convert("RGBA")

    def width(self, s):
        return sum(self.chars.get(ord(c), {"xadvance": 0})["xadvance"] for c in s)

    def draw(self, img, x, y, s, color, just="left"):
        if just == "center":
            x -= self.width(s) / 2
        x = int(round(x)); y = int(round(y))
        for c in s:
            g = self.chars.get(ord(c))
            if not g:
                continue
            if g["width"] > 0:
                a = self.sheet.crop((g["x"], g["y"], g["x"] + g["width"], g["y"] + g["height"])).split()[3]
                img.paste(Image.new("RGB", a.size, color), (x + g["xoffset"], y + g["yoffset"]), a)
            x += g["xadvance"]


_cache = {}
def tw(i): return _cache.setdefault("tw%d" % i, BmFont(TW_FILE[max(0, min(i, 13))]))
def wx(i): return _cache.setdefault("wx%d" % i, BmFont("wx-%d" % WX_PX[max(0, min(i, 7))]))


def fit_tw(maxw, maxh, n):
    idx = 0
    for i in range(10):
        if TW_ADV[i] * n <= maxw and TW_CAP[i] <= maxh: idx = i
        else: break
    return idx

def sub_tw():
    w = SW[0]
    return 13 if w >= 470 else 12 if w >= 400 else 11 if w >= 270 else 10

def cap_tw(maxw, maxh, n, ref):
    s = sub_tw()
    rw = tw(s).width(ref)
    if rw <= maxw and TW_CAP[s] <= maxh: return s
    return fit_tw(maxw, maxh, min(n, rw / TW_ADV[s]))

def fit_wx(maxw, maxh):
    idx = 0
    for i in range(len(WX_PX)):
        if WX_ADV[i] <= maxw and WX_CAP[i] <= maxh: idx = i
        else: break
    return idx

def pad_of(w, h): return max(2, int(min(w, h) * 0.06))


class Dc:
    def __init__(self, w, h, col, scale):
        self.img = Image.new("RGB", (w * 4, h * 4), col["bg"])  # 4x 슈퍼샘플은 도형만
        self.w, self.h, self.c, self.scale = w, h, col, scale
        self.d = ImageDraw.Draw(self.img)
        self.texts = []

    def poly(self, pts, color):
        self.d.polygon([(px * 4, py * 4) for px, py in pts], fill=color)

    def circle(self, cx, cy, r, color, fill=False, pen=1):
        box = [(cx - r) * 4, (cy - r) * 4, (cx + r) * 4, (cy + r) * 4]
        if fill: self.d.ellipse(box, fill=color)
        else: self.d.ellipse(box, outline=color, width=max(1, int(pen * 4)))

    def arc(self, cx, cy, r, a0, a1, color, pen):
        # CIQ: 0=3시, 반시계 +  /  PIL: 0=3시, 시계 +
        box = [(cx - r - pen / 2) * 4, (cy - r - pen / 2) * 4, (cx + r + pen / 2) * 4, (cy + r + pen / 2) * 4]
        self.d.arc(box, -a1, -a0, fill=color, width=int(pen * 4))

    def line(self, x0, y0, x1, y1, color):
        self.d.line([x0 * 4, y0 * 4, x1 * 4, y1 * 4], fill=color, width=4)

    def text(self, font, x, y, s, color, just="left"):
        self.texts.append((font, x, y, s, color, just))

    def finish(self):
        img = self.img.resize((self.w, self.h), Image.LANCZOS)
        for font, x, y, s, color, just in self.texts:
            font.draw(img, x, y, s, color, just)
        return img


def nav_arrow(dc, cx, cy, s, deg, color):
    r = math.radians(deg); c, sn = math.cos(r), math.sin(r)
    dc.poly([(cx + NAV_X[i] * s * c - NAV_Y[i] * s * sn, cy + NAV_X[i] * s * sn + NAV_Y[i] * s * c) for i in range(4)], color)


def value_stack(dc, tx, y, twid, h, pad, main, ref, main_slots, sub, sub_slots, arrow):
    c = dc.c
    avail = h - 2 * pad
    has_sub = sub_slots > 0
    mi = cap_tw(twid, int(avail * (0.6 if has_sub else 0.85)), main_slots + 0.2, ref)
    si = 0; gapv = 0
    if has_sub:
        si = fit_tw(twid, int(avail * 0.3), sub_slots)
        while si > 0 and TW_CAP[si] > TW_CAP[mi] * 0.7: si -= 1
        gapv = max(2, TW_CAP[si] // 2)
    total = TW_CAP[mi] + (gapv + TW_CAP[si] if has_sub else 0)
    top = y + (h - total) // 2
    cx = tx + twid // 2
    dc.text(tw(mi), cx, top, main, c["fg"], "center")
    if has_sub and (sub is not None or arrow is not None):
        sy = top + TW_CAP[mi] + gapv
        subw = tw(si).width(sub) if sub else 0
        a = TW_CAP[si] / 2.0 if arrow is not None else 0
        ag = max(2, int(a / 2)) if (arrow is not None and sub) else 0
        x0 = cx - (a * 2 + ag + subw) / 2
        if arrow is not None: nav_arrow(dc, x0 + a, sy + a, a, arrow, c["dim"])
        if sub: dc.text(tw(si), x0 + a * 2 + ag, sy, sub, c["dim"])


def p_wind(dc, x, y, w, h, data):
    c = dc.c; pad = pad_of(w, h)
    d = min(h - 2 * pad, int(w * 0.42)); arc_pen = max(3, int(d * 0.15))
    r = (d - arc_pen) / 2.0; cx = x + pad + d / 2.0; cy = y + h / 2.0
    rel = (data["wind_from"] - data["heading"]) % 360
    col = c["red"] if (rel < 60 or rel >= 300) else (c["blue"] if 150 <= rel < 210 else c["gray"])
    a = 90 - rel
    dc.arc(cx, cy, r, a + 15, a + 345, col, arc_pen)
    nav_arrow(dc, cx, cy, r * 0.58, 0, c["fg"])
    tx = x + pad + d + max(3, pad); twid = x + w - pad - tx
    if twid < 14: return
    v = data["wind_speed"]
    unit = data.get("unit", "m/s")
    value_stack(dc, tx, y, twid, h, pad, ("%d" % v) if v >= 10 else ("%.1f" % v), "0.0", 3, unit, len(unit) + 1, None)


def p_forecast(dc, x, y, w, h, data):
    c = dc.c; pad = pad_of(w, h)
    wi = fit_wx(int((w - 2 * pad) * 0.5), h - 2 * pad)
    icon = data.get("fc_icon", "C")
    boxw = WX_ADV[wi]
    dc.text(wx(wi), x + pad + boxw / 2, y + (h - WX_CAP[wi]) // 2, icon, c["accent"], "center")
    tx = x + pad + boxw + max(3, pad); twid = x + w - pad - tx
    if twid < 14: return
    pop = data.get("fc_pop", 30)
    hour = data.get("fc_hour", "15")
    value_stack(dc, tx, y, twid, h, pad, hour, "00" if hour[-1].isdigit() else "00p", 2 if hour[-1].isdigit() else 3,
                None if pop is None else "%d%%" % pop, 6.4, data.get("fc_toward", 120))


def sun_row(dc, x, y, w, h, wi, ti, icon, text, dim):
    c = dc.c
    iw = wx(wi).width(icon); tw_ = tw(ti).width(text); gap = max(2, TW_CAP[ti] // 4)
    x0 = max(x, x + (w - (iw + gap + tw_)) // 2)
    dc.text(wx(wi), x0, y + (h - WX_CAP[wi]) // 2, icon, c["dim"] if dim else c["accent"])
    dc.text(tw(ti), x0 + iw + gap, y + (h - TW_CAP[ti]) // 2, text, c["dim"] if dim else c["fg"])


def p_sun(dc, x, y, w, h, data):
    pad = pad_of(w, h)
    rise, sset = data["rise"], data["set"]
    n = 5 if rise[-1].isdigit() else 6; iw_ = w - 2 * pad; ih = h - 2 * pad
    rowh = ih // 2
    awi = fit_wx(int(iw_ * 0.38), rowh); ati = cap_tw(iw_ - WX_ADV[awi] - pad, int(rowh * 0.8), n, "00:00" if n == 5 else "00:00p")
    colw = (iw_ - pad) // 2
    bwi = fit_wx(int(colw * 0.42), ih); bti = cap_tw(colw - WX_ADV[bwi] - 2, int(ih * 0.6), n, "00:00" if n == 5 else "00:00p")
    if TW_CAP[ati] >= TW_CAP[bti]:
        sun_row(dc, x + pad, y + pad, iw_, rowh, awi, ati, "G", rise, data.get("rise_dim", True))
        sun_row(dc, x + pad, y + pad + rowh, iw_, ih - rowh, awi, ati, "g", sset, data.get("set_dim", False))
    else:
        sun_row(dc, x + pad, y + pad, colw, ih, bwi, bti, "G", rise, data.get("rise_dim", True))
        sun_row(dc, x + pad + colw + pad, y + pad, colw, ih, bwi, bti, "g", sset, data.get("set_dim", False))


def p_moon(dc, x, y, w, h, data):
    c = dc.c; pad = pad_of(w, h)
    el, illum, age = data["moon"]
    d = min(h - 2 * pad, int(w * 0.42)); r = d / 2.0 - 1
    cx = x + pad + d / 2.0; cy = y + h / 2.0
    dc.circle(cx, cy, r, c["moon_dark"], fill=True)
    k = math.cos(math.radians(el))
    if k <= 0.995:
        side = 1 if el < 180 else -1
        pts = [(cx + side * r * math.cos(-math.pi / 2 + math.pi * i / 12), cy + r * math.sin(-math.pi / 2 + math.pi * i / 12)) for i in range(13)]
        pts += [(cx + side * k * r * math.cos(-math.pi / 2 + math.pi * j / 12), cy + r * math.sin(-math.pi / 2 + math.pi * j / 12)) for j in range(12, -1, -1)]
        dc.poly(pts, c["accent"])
    tx = x + pad + d + max(3, pad); twid = x + w - pad - tx
    if twid < 14: return
    value_stack(dc, tx, y, twid, h, pad, "%d%%" % min(100, int(illum + 0.5)), "100%", 4, "%.1fd" % age, 6, None)


PANELS = [p_wind, p_forecast, p_sun, p_moon]


def render(w, h, screen_w, mode, col, data, layout_mode=0):
    SW[0] = screen_w
    s = screen_w / 246.0
    dc = Dc(w, h, col, s)
    if layout_mode == 1 or w < 200 * s: kind = "single"
    elif h >= 120 * s: kind = "quad"
    else: kind = "double"
    if kind == "quad":
        hw, hh = w // 2, h // 2
        p_wind(dc, 0, 0, hw, hh, data); p_forecast(dc, hw, 0, w - hw, hh, data)
        p_sun(dc, 0, hh, hw, h - hh, data); p_moon(dc, hw, hh, w - hw, h - hh, data)
        dc.line(hw, 4, hw, h - 4, col["line"]); dc.line(4, hh, w - 4, hh, col["line"])
    elif kind == "double":
        hw = w // 2
        p_wind(dc, 0, 0, hw, h, data)
        PANELS[2 if mode == 0 else mode](dc, hw, 0, w - hw, h, data)
        dc.line(hw, 4, hw, h - 4, col["line"])
    else:
        PANELS[mode](dc, 0, 0, w, h, data)
    return dc.finish(), kind


def sample_data():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=9)))
    mid = now.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    rise, sset = sun_calc(37.5784, 126.9769, mid)
    def fmt(sec): sec = int(sec) % 86400; return "%d:%02d" % (sec // 3600, sec % 3600 // 60)
    return dict(wind_from=300, heading=0, wind_speed=3.4, rise=fmt(rise), set=fmt(sset),
                moon=moon_calc(now.timestamp()))


def _mod(x, m): return x - m * math.floor(x / m)

def sun_calc(lat, lng, today):
    R = math.pi / 180
    jd = (today + 43200) / 86400.0 + 2440587.5
    n = math.floor(jd - 2451545.0 + 0.5); j = n - lng / 360.0
    m = _mod(357.5291 + 0.98560028 * j, 360)
    c = 1.9148 * math.sin(m * R) + 0.02 * math.sin(2 * m * R) + 0.0003 * math.sin(3 * m * R)
    l = _mod(m + c + 180 + 102.9372, 360)
    jt = 2451545.0 + j + 0.0053 * math.sin(m * R) - 0.0069 * math.sin(2 * l * R)
    sd = math.sin(l * R) * math.sin(23.4397 * R); cd = math.cos(math.asin(sd))
    cw = (math.sin(-0.833 * R) - math.sin(lat * R) * sd) / (math.cos(lat * R) * cd)
    w = math.acos(max(-1, min(1, cw))) / R / 360
    return (jt - w - 2440587.5) * 86400 - today, (jt + w - 2440587.5) * 86400 - today

def moon_calc(unix):
    R = math.pi / 180
    d = unix / 86400.0 + 2440587.5 - 2451545.0
    lm = 218.316 + 13.176396 * d + 6.289 * math.sin(_mod(134.963 + 13.064993 * d, 360) * R)
    g = _mod(357.529 + 0.98560028 * d, 360)
    ls = 280.459 + 0.98564736 * d + 1.915 * math.sin(g * R) + 0.020 * math.sin(2 * g * R)
    el = _mod(lm - ls, 360)
    return el, (1 - math.cos(el * R)) / 2 * 100, el / 360 * 29.530588853


def main():
    data = sample_data()
    cases = [  # (label, w, h, screen_w, mode, dark)
        ("540 1/8 full-width 246x64", 246, 64, 246, 3, False),
        ("540 246x106", 246, 106, 246, 1, False),
        ("540 half 122x66 (wind)", 122, 66, 246, 0, False),
        ("540 half 122x66 (sun)", 122, 66, 246, 2, False),
        ("540 246x160", 246, 160, 246, 0, False),
        ("540 246x160 dark", 246, 160, 246, 0, True),
        ("1040 282x93", 282, 93, 282, 1, False),
        ("1040 140x93 (moon)", 140, 93, 282, 3, False),
        ("1040 282x155", 282, 155, 282, 0, False),
        ("1050 480x160", 480, 160, 480, 2, False),
        ("1050 239x160 (forecast)", 239, 160, 480, 1, False),
        ("1050 480x266 dark", 480, 266, 480, 0, True),
        ("540 forecast 1p", 122, 66, 246, 1, False),
        ("540 forecast 9p", 122, 66, 246, 1, False),
        ("540 forecast 11p", 122, 66, 246, 1, False),
    ]
    tiles = []
    for label, w, h, sw, mode, dark in cases:
        d = dict(data)
        if label.startswith("540 forecast "):
            d.update(fc_hour=label.split()[-1], fc_icon={"1p": "A", "9p": "c", "11p": "R"}[label.split()[-1]])
        img, kind = render(w, h, sw, mode, DARK if dark else LIGHT, d)
        tiles.append(("%s  [%s]" % (label, kind), img))
    W = 1000; x = y = 10; rowh = 0
    pos = []
    for label, img in tiles:
        if x + img.width + 10 > W: x = 10; y += rowh + 30; rowh = 0
        pos.append((x, y, label, img)); x += img.width + 20; rowh = max(rowh, img.height)
    sheet = Image.new("RGB", (W, y + rowh + 30), (200, 205, 215))
    dr = ImageDraw.Draw(sheet)
    for x, y, label, img in pos:
        dr.text((x, y), label, fill=(0, 0, 0))
        sheet.paste(img, (x, y + 14))
        dr.rectangle([x - 1, y + 13, x + img.width, y + 14 + img.height], outline=(0, 120, 220))
    out = os.path.join(ROOT, "tools", "preview.png")
    sheet.save(out)
    print(out, data["rise"], data["set"], "moon %.0f%%" % data["moon"][1])


if __name__ == "__main__":
    main()
