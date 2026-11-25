"""
make_assets.py - Connect IQ 스토어용 이미지 생성

    python store/make_assets.py            -> store/images/*.png

  cover.png              앱 아이콘(대표 이미지) 500x500, 둘레 10px 여백, 투명 배경
  hero_ko.png / _en.png  히어로 1440x720 (글자가 있어서 언어별)
  screen{1..5}_ko/en.png 화면 이미지 500x500 (업로드 한도 150KB 이하로 저장)

화면 안의 데이터 필드는 tools/preview.py 렌더러로 그린다
(= 앱과 같은 비트맵 폰트·같은 배치 계산). Pillow 필요.
"""
import io, math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import preview as pv  # noqa: E402

OUT = os.path.join(HERE, "images")
os.makedirs(OUT, exist_ok=True)

# ---- 글꼴 -------------------------------------------------------------------
def _find_font(cands, want="KR"):
    for path in cands:
        if not os.path.exists(path):
            continue
        if path.endswith(".ttc"):
            for i in range(10):
                try:
                    f = ImageFont.truetype(path, 20, index=i)
                    if want in " ".join(f.getname()):
                        return path, i
                except OSError:
                    break
        else:
            return path, 0
    raise SystemExit("한글 글꼴을 찾을 수 없음: " + ", ".join(cands))

KR_BOLD = _find_font(["/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc",
                      "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
                      "C:/Windows/Fonts/malgunbd.ttf"])
KR_REG = _find_font(["/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc",
                     "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                     "C:/Windows/Fonts/malgun.ttf"])
TITILLIUM = os.path.join(ROOT, "tools", "ttf", "TitilliumWeb-Bold.ttf")

def kb(size): return ImageFont.truetype(KR_BOLD[0], size, index=KR_BOLD[1])
def kr(size): return ImageFont.truetype(KR_REG[0], size, index=KR_REG[1])
def ti(size): return ImageFont.truetype(TITILLIUM, size)

ORANGE = (255, 106, 0)
BLUE_LINE = (0, 120, 215)

# ---- 공통 데이터 ----------------------------------------------------------------
BASE = dict(wind_from=10, heading=0, wind_speed=4.6, unit="m/s",
            rise="7:14", set="17:20", rise_dim=True, set_dim=False,
            moon=(96.5, 55.6, 7.9), fc_icon="C", fc_hour="15", fc_pop=30, fc_toward=120)

def D(**kw):
    d = dict(BASE); d.update(kw); return d

HEAD = dict(wind_from=8)      # 맞바람 (빨강)
TAIL = dict(wind_from=185)    # 뒷바람 (파랑)
CROSS = dict(wind_from=100)   # 옆바람 (회색)

def moon(el):
    return (el, (1 - math.cos(math.radians(el))) / 2 * 100, el / 360 * 29.530588853)


# ---- 화면 합성 ------------------------------------------------------------------
def page(rows, screen_w, screen_h, dark):
    """rows: [ (h, [ (w, mode, data), ... ]), ... ]  -> 기기 화면 이미지"""
    col = pv.DARK if dark else pv.LIGHT
    img = Image.new("RGB", (screen_w, screen_h), col["bg"])
    dr = ImageDraw.Draw(img)
    y = 0
    for ri, (h, cells) in enumerate(rows):
        x = 0
        for ci, (w, mode, data) in enumerate(cells):
            tile, _ = pv.render(w, h, screen_w, mode, col, data)
            img.paste(tile, (x, y))
            x += w
            if ci < len(cells) - 1:
                dr.line([x, y, x, y + h - 1], fill=BLUE_LINE, width=2 if screen_w >= 480 else 1)
                x += 2 if screen_w >= 480 else 1
        y += h
        if ri < len(rows) - 1:
            dr.line([0, y, screen_w, y], fill=BLUE_LINE, width=2 if screen_w >= 480 else 1)
            y += 2 if screen_w >= 480 else 1
    return img


def device(screen, side=16, top=22, bottom=30, radius=26):
    """화면 둘레에 무광 검정 사이클 컴퓨터 본체를 그린다 (로고 없음)."""
    sw, sh = screen.size
    W, H = sw + side * 2, sh + top + bottom
    ss = 3
    body = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([0, 0, W * ss - 1, H * ss - 1], radius=radius * ss, fill=(28, 30, 34, 255))
    d.rounded_rectangle([3 * ss, 3 * ss, W * ss - 3 * ss, H * ss - 3 * ss], radius=(radius - 3) * ss,
                        outline=(58, 62, 70, 255), width=2 * ss)
    d.rounded_rectangle([(side - 4) * ss, (top - 4) * ss, (side + sw + 4) * ss, (top + sh + 4) * ss],
                        radius=6 * ss, fill=(8, 9, 11, 255))
    body = body.resize((W, H), Image.LANCZOS)
    body.paste(screen, (side, top))
    # 유리 반사 한 줄
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    gd.polygon([(side, top), (side + sw * 0.55, top), (side + sw * 0.25, top + sh), (side, top + sh)],
               fill=(255, 255, 255, 14))
    body.alpha_composite(gl)
    return body


def shadowed(img, blur=18, offset=(0, 14), alpha=110):
    pad = blur * 3
    W, H = img.size
    out = Image.new("RGBA", (W + pad * 2, H + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0))
    mask = img.split()[3].point(lambda a: a * alpha // 255)
    sh.paste(Image.new("RGBA", img.size, (0, 0, 0, 255)), (pad + offset[0], pad + offset[1]), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(sh)
    out.alpha_composite(img, (pad, pad))
    return out, pad


def gradient(W, H, top, bottom):
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / max(1, H - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((W, H)).convert("RGBA")


def wind_streaks(img, n, color, seed=7):
    import random
    rnd = random.Random(seed)
    W, H = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        y = rnd.uniform(0, H); x = rnd.uniform(-200, W); L = rnd.uniform(120, 420)
        a = rnd.randint(10, 28)
        pts = [(x + L * t, y + math.sin(t * math.pi * 1.2) * 12) for t in [i / 20 for i in range(21)]]
        d.line(pts, fill=color + (a,), width=rnd.choice([1, 2, 2, 3]))
    img.alpha_composite(layer)


def save_png(img, name, limit_kb):
    path = os.path.join(OUT, name)
    rgb = img
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    if limit_kb and buf.tell() > limit_kb * 1024:
        has_alpha = img.mode == "RGBA"
        for colors in (256, 192, 128):
            q = img.convert("RGBA").quantize(colors=colors, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)
            buf = io.BytesIO()
            q.save(buf, "PNG", optimize=True)
            if buf.tell() <= limit_kb * 1024:
                break
    with open(path, "wb") as f:
        f.write(buf.getvalue())
    print("  %-18s %4dx%-4d %6.1f KB" % (name, img.size[0], img.size[1], buf.tell() / 1024))


# ---- 화면 구성: 10분할 (2열 x 5행) -----------------------------------------------
#  840 = 246x322, 칸 122x63 / 1050 = 480x800, 칸 239x158 (다른 zz+ 앱 동작화면과 같은 배치)
def grid10(cells, sw, sh, dark):
    """cells: 10개 (mode, data), 왼쪽→오른쪽, 위→아래"""
    lw = 2 if sw >= 480 else 1
    left = (sw - lw) // 2
    right = sw - lw - left
    rows_h = sh - 4 * lw
    hs = [rows_h // 5 + (1 if i < rows_h % 5 else 0) for i in range(5)]
    rows = []
    for r in range(5):
        (m1, d1), (m2, d2) = cells[2 * r], cells[2 * r + 1]
        rows.append((hs[r], [(left, m1, d1), (right, m2, d2)]))
    return page(rows, sw, sh, dark)

# mode: 0 바람, 1 예보, 2 일출일몰, 3 달
def page_overview_840(dark=False):
    return grid10([
        (0, D(**HEAD)), (1, D()),
        (2, D()), (3, D()),
        (0, D(**TAIL, wind_speed=3.2)), (1, D(fc_icon="A", fc_hour="18", fc_pop=0, fc_toward=200)),
        (3, D(moon=moon(150))), (2, D(rise_dim=True, set_dim=True, rise="7:14", set="17:20")),
        (0, D(**CROSS, wind_speed=8.1)), (1, D(fc_icon="R", fc_hour="21", fc_pop=70, fc_toward=60)),
    ], 246, 322, dark)

def page_wind_840(dark=True):
    return grid10([
        (0, D(**HEAD, wind_speed=6.2)), (0, D(**TAIL, wind_speed=3.8)),
        (0, D(**CROSS, wind_speed=12.4)), (0, D(wind_from=300, wind_speed=2.1)),
        (1, D(fc_icon="A", fc_hour="11", fc_pop=0, fc_toward=200)), (2, D()),
        (0, D(wind_from=170, wind_speed=5.5)), (0, D(wind_from=40, wind_speed=9.7)),
        (3, D(moon=moon(52))), (0, D(wind_from=250, wind_speed=1.4)),
    ], 246, 322, dark)

def page_forecast_840(dark=False):
    return grid10([
        (1, D(fc_icon="C", fc_hour="15", fc_pop=30, fc_toward=120)), (1, D(fc_icon="R", fc_hour="16", fc_pop=70, fc_toward=60)),
        (1, D(fc_icon="A", fc_hour="17", fc_pop=0, fc_toward=200)), (1, D(fc_icon="c", fc_hour="21", fc_pop=10, fc_toward=300)),
        (2, D()), (2, D(rise_dim=True, set_dim=True)),
        (0, D(**CROSS)), (3, D()),
        (2, D(rise_dim=False, set_dim=False, rise="6:58", set="17:31")), (1, D(fc_icon="R", fc_hour="23", fc_pop=90, fc_toward=30)),
    ], 246, 322, dark)

def page_moon_840(dark=True):
    return grid10([
        (3, D(moon=moon(30))), (3, D(moon=moon(70))),
        (3, D(moon=moon(110))), (3, D(moon=moon(180))),
        (3, D(moon=moon(235))), (3, D(moon=moon(290))),
        (0, D(**HEAD)), (2, D()),
        (1, D()), (3, D(moon=moon(330))),
    ], 246, 322, dark)

def page_overview_1050(dark=False):
    return grid10([
        (0, D(**HEAD)), (1, D()),
        (2, D()), (3, D()),
        (0, D(**TAIL, wind_speed=3.2)), (1, D(fc_icon="A", fc_hour="18", fc_pop=0, fc_toward=200)),
        (3, D(moon=moon(150))), (2, D(rise_dim=True, set_dim=True)),
        (0, D(**CROSS, wind_speed=8.1)), (1, D(fc_icon="R", fc_hour="21", fc_pop=70, fc_toward=60)),
    ], 480, 800, dark)


# ---- 1) 대표 이미지 (앱 아이콘) -----------------------------------------------------
# zz...Plus 시리즈와 같은 형식: 남색 타일 + 흰 화면(아이콘 / 보조값 / 큰 빨간 값) + 앱 이름 + 캡션
WXICON_TTF = os.path.join(ROOT, "tools", "ttf", "weathericons-regular-webfont.ttf")

def make_cover():
    S = 4
    W = 500 * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    p = 10 * S
    d.rounded_rectangle([p, p, W - p - 1, W - p - 1], radius=34 * S, fill=(26, 30, 39, 255))

    # 흰 화면
    sx0, sy0, sx1, sy1 = 58 * S, 50 * S, 442 * S, 318 * S
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=22 * S, fill=(244, 244, 244, 255))
    ink = (20, 20, 20, 255)
    red = (226, 0, 0, 255)

    # 왼쪽: 큰 바람 링(맞바람 빨강, 왼쪽 위에 구멍) + 진행방향 화살표 = 주인공
    cx, cy = sx0 + 114 * S, (sy0 + sy1) / 2
    r, pen = 88 * S, 28 * S
    gap = 90 - 330
    d.arc([cx - r, cy - r, cx + r, cy + r], -(gap + 340), -(gap + 20), fill=red, width=pen)
    sa = 48 * S
    d.polygon([(cx + pv.NAV_X[i] * sa, cy + pv.NAV_Y[i] * sa) for i in range(4)], fill=ink)

    # 오른쪽 위: 날씨 아이콘(주황) + 일몰 시각 / 오른쪽 아래: 풍속(보조)
    colx = (cx + r + pen / 2 + 12 * S + sx1 - 14 * S) / 2
    wxf = ImageFont.truetype(WXICON_TTF, 58 * S)
    d.text((colx, sy0 + 62 * S), "\uf002", font=wxf, fill=(255, 106, 0, 255), anchor="mm")
    d.text((colx, sy0 + 140 * S), "17:20", font=ti(52 * S), fill=ink, anchor="mm")
    num, unit = ti(58 * S), ti(26 * S)
    nw = d.textlength("4.6", font=num); uw = d.textlength("m/s", font=unit)
    x0 = colx - (nw + 6 * S + uw) / 2
    base = sy1 - 30 * S
    d.text((x0, base), "4.6", font=num, fill=ink, anchor="ls")
    d.text((x0 + nw + 6 * S, base), "m/s", font=unit, fill=(90, 90, 90, 255), anchor="ls")

    # 앱 이름 + 캡션
    d.text((W / 2, 384 * S), "zzWeatherPlus", font=ti(64 * S), fill=(255, 255, 255, 255), anchor="mm")
    cap = "WIND  /  FORECAST  /  SUN  /  MOON"
    cf = ti(19 * S)
    spacing = 1.6 * S
    total = sum(d.textlength(ch, font=cf) + spacing for ch in cap) - spacing
    cxp = W / 2 - total / 2
    for ch in cap:
        d.text((cxp, 446 * S), ch, font=cf, fill=(214, 140, 72, 255), anchor="lm")
        cxp += d.textlength(ch, font=cf) + spacing

    img = img.resize((500, 500), Image.LANCZOS)
    save_png(img, "cover.png", 300)


# ---- 2) 히어로 1440x720 ------------------------------------------------------------
HERO_TXT = {
    "ko": dict(kicker="Garmin Edge 데이터 필드",
               title="zz날씨", tag="바람 · 일기예보 · 일출일몰 · 달",
               bullets=[((234, 64, 44), "진행방향 기준 맞바람·뒷바람을 한눈에"),
                        ((255, 170, 0), "12시간 예보와 강수확률"),
                        ((110, 170, 255), "큰 Titillium 숫자로 라이딩 중에도 또렷하게")],
               devices="Edge 540 · 550 · 840 · 850 · 1040 · 1050 · 1060"),
    "en": dict(kicker="Garmin Edge Data Field",
               title="zzWeather", tag="Wind · Forecast · Sunrise/Sunset · Moon",
               bullets=[((234, 64, 44), "Headwind or tailwind, relative to your heading"),
                        ((255, 170, 0), "12-hour forecast with rain chance"),
                        ((110, 170, 255), "Big Titillium digits, readable at speed")],
               devices="Edge 540 · 550 · 840 · 850 · 1040 · 1050 · 1060"),
}

def make_hero(lang):
    t = HERO_TXT[lang]
    W, H = 1440, 720
    img = gradient(W, H, (14, 28, 48), (8, 14, 26))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([820, -120, 1620, 700], fill=(40, 110, 200, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120)))
    wind_streaks(img, 40, (150, 200, 255), seed=11)

    # 기기: 840(어두운 모드) 앞, 1050(밝은 모드) 뒤
    big = device(page_overview_1050(dark=False), side=22, top=30, bottom=40, radius=34)
    big = big.resize((int(big.width * 0.70), int(big.height * 0.70)), Image.LANCZOS)
    small = device(page_wind_840(dark=True), side=16, top=22, bottom=30, radius=26)
    small = small.resize((int(small.width * 1.12), int(small.height * 1.12)), Image.LANCZOS)
    b, bp = shadowed(big, blur=22, offset=(0, 18), alpha=150)
    s_, sp = shadowed(small, blur=18, offset=(0, 14), alpha=170)
    img.alpha_composite(b, (1040 - bp, 52 - bp))
    img.alpha_composite(s_, (800 - sp, 222 - sp))

    d = ImageDraw.Draw(img)
    x = 96
    d.text((x, 150), t["kicker"], font=kr(30), fill=(150, 185, 230))
    if lang == "ko":
        f = kb(104)
        d.text((x - 4, 186), t["title"], font=f, fill=(255, 255, 255))
        tw_ = d.textlength(t["title"], font=f)
    else:
        f = ti(118)
        d.text((x - 4, 168), t["title"], font=f, fill=(255, 255, 255))
        tw_ = d.textlength(t["title"], font=f)
    d.text((x + tw_ + 2, 168 if lang == "ko" else 160), "+", font=ti(128), fill=ORANGE)
    d.text((x, 336), t["tag"], font=kb(34) if lang == "ko" else ti(40), fill=(220, 232, 248))
    y = 418
    for color, line in t["bullets"]:
        d.ellipse([x, y + 12, x + 14, y + 26], fill=color)
        d.text((x + 30, y), line, font=kr(27) if lang == "ko" else ti(30), fill=(225, 233, 245))
        y += 52
    d.text((x, 610), t["devices"], font=kr(22) if lang == "ko" else ti(24), fill=(130, 155, 190))
    save_png(img.convert("RGB"), "hero_%s.png" % lang, 0)


# ---- 3) 화면 이미지 500x500 ----------------------------------------------------------
SCREENS = [
    ("screen1", page_overview_840, False,
     ("바람·예보·일출일몰·달", "칸마다 표시 항목 선택 · 탭하면 전환"),
     ("Wind, forecast, sunrise/sunset & moon", "Choose an item per field · tap to switch")),
    ("screen2", page_wind_840, True,
     ("링의 구멍 = 바람이 들어오는 쪽", "맞바람 빨강 · 옆바람 회색 · 뒷바람 파랑"),
     ("The gap in the ring is where wind comes in", "Red headwind · gray crosswind · blue tailwind")),
    ("screen3", page_forecast_840, False,
     ("12시간 일기예보 + 강수확률", "일출·일몰은 지난 시각을 흐리게 표시"),
     ("12-hour forecast with rain chance", "Sunrise / sunset, past times dimmed")),
    ("screen4", page_moon_840, True,
     ("실제 위상으로 그린 달 모양과 밝기", "야간 라이딩 참고용 · 월령 함께 표시"),
     ("Moon drawn from its real phase", "Brightness % and moon age for night rides")),
    ("screen5", page_overview_1050, False,
     ("1040 · 1050 · 1060 큰 화면도 꽉 차게", "기기 해상도에 맞춰 글자 크기 자동 선택"),
     ("Fills big screens: 1040 · 1050 · 1060", "Font size picked for every resolution")),
]

def make_screen(name, page_fn, dark, cap, lang):
    W = 500
    img = gradient(W, W, (242, 245, 250), (222, 229, 240)) if not dark else gradient(W, W, (24, 32, 46), (10, 14, 22))
    d = ImageDraw.Draw(img)
    title_c = (20, 30, 48) if not dark else (255, 255, 255)
    sub_c = (80, 92, 112) if not dark else (165, 182, 205)
    def fit(make, size, text, maxw=468):
        while size > 12 and d.textlength(text, font=make(size)) > maxw:
            size -= 1
        return make(size)
    tf = fit(kb, 25, cap[0]) if lang == "ko" else fit(ti, 28, cap[0])
    sf = fit(kr, 16, cap[1]) if lang == "ko" else fit(ti, 19, cap[1])
    d.text((W / 2, 30), cap[0], font=tf, fill=title_c, anchor="mm")
    d.text((W / 2, 62), cap[1], font=sf, fill=sub_c, anchor="mm")

    scr = page_fn(dark)
    if scr.width >= 480:   # 1050: 축소
        dev = device(scr, side=22, top=30, bottom=40, radius=34)
        k = 400 / dev.height
        dev = dev.resize((int(dev.width * k), int(dev.height * k)), Image.LANCZOS)
    else:                  # 840: 실제 픽셀 그대로 (비트맵 폰트 선명)
        dev = device(scr)
    sh, sp = shadowed(dev, blur=12, offset=(0, 8), alpha=120)
    img.alpha_composite(sh, ((W - dev.width) // 2 - sp, 88 - sp))
    save_png(img.convert("RGB"), "%s.png" % name, 150)


def main():
    print("store/images:")
    make_cover()
    # 히어로는 한국어·영어 두 장, 화면 5장은 영어만
    make_hero("ko")
    make_hero("en")
    for name, fn, dark, cko, cen in SCREENS:
        make_screen(name, fn, dark, cen, "en")


if __name__ == "__main__":
    main()
