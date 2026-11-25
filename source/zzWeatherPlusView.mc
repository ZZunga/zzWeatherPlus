using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// zzWeatherPlus 데이터 필드.
//   바람(풍향 링 + 풍속) / 시간별 예보 / 일출·일몰 / 달 위상·밝기
// 칸 크기에 따라 1개(SINGLE) / 2개(DOUBLE) / 4개(QUAD) 패널을 그린다.
// 레이아웃 XML 없이 코드로 그린다 (zzCadence 와 같은 방식).
class zzWeatherPlusView extends WatchUi.DataField {

    hidden var mTwCache;
    hidden var mWxCache;

    hidden var mW = 0;
    hidden var mH = 0;
    hidden var mKind = Layout.SLOT_SINGLE;

    hidden var mModeOverride = null;   // 터치로 바꾼 표시 항목 (설정 변경 시 해제)
    hidden var mHeading = 0.0;         // 진행/나침반 방향 (도)
    hidden var mTick = 0;

    hidden var mSun = null;            // [일출초, 일몰초] or null
    hidden var mSunTick = -100000;
    hidden var mSunDay = -1;

    // 색 (onUpdate 마다 배경에 맞춰 갱신)
    hidden var mBg = Graphics.COLOR_WHITE;
    hidden var mClearBg = Graphics.COLOR_WHITE;
    hidden var mFg = Graphics.COLOR_BLACK;
    hidden var mDim = Graphics.COLOR_DK_GRAY;
    hidden var mLine = Graphics.COLOR_LT_GRAY;
    hidden var mAccent = Graphics.COLOR_ORANGE;
    hidden var mDark = false;

    // wind.svg (Font Awesome location-arrow) 를 위쪽 방향으로 정규화한 꼭짓점
    // 끝(0,-1) / 오른날개(0.848,1) / 안쪽 홈(0,0.398) / 왼날개(-0.848,1)
    const NAV_X = [ 0.0, 0.848, 0.0,   -0.848 ];
    const NAV_Y = [ -1.0, 1.0,  0.398,  1.0   ];

    function initialize() {
        DataField.initialize();
        mTwCache = new [Layout.TW_ALL];
        mWxCache = new [Layout.WX_N];
        // App.onStart 에서 이미 강제 저장했다. 여기선 그 사이 GPS 가 잡혔으면 갱신만.
        LocationStore.capture(false);
    }

    // ---- 이벤트 ---------------------------------------------------------

    function onSettingsChanged() {
        mModeOverride = null;
        mW = 0;              // 다음 onUpdate 에서 칸 분류 다시
        mSunTick = -100000;  // 시간 표시 형식이 바뀌었을 수 있음
    }

    function onTimerStop() {
        LocationStore.flush();
    }

    function onTimerReset() {
        LocationStore.flush();
        mModeOverride = null;
    }

    // 터치: 표시 항목 순환. 처리했으면 true.
    function nextMode() {
        var cfg = Config.read();
        if (!cfg.touch) {
            return false;
        }
        if (mKind == Layout.SLOT_DOUBLE) {
            // 2개 칸: 왼쪽이 항상 바람이므로 오른쪽은 예보 → 일출일몰 → 달만 순환
            var shown = rightMode(currentMode());
            mModeOverride = (shown >= Config.MODE_MOON) ? Config.MODE_FORECAST : shown + 1;
        } else {
            mModeOverride = (currentMode() + 1) % Config.NMODES;
        }
        WatchUi.requestUpdate();
        return true;
    }

    // 2개 칸 오른쪽에 실제로 보이는 항목 (설정이 바람이면 일출·일몰)
    hidden function rightMode(mode) {
        return (mode == Config.MODE_WIND) ? Config.MODE_SUN : mode;
    }

    hidden function currentMode() {
        return (mModeOverride != null) ? mModeOverride : Config.read().mode;
    }

    function onLayout(dc) {
        mW = dc.getWidth();
        mH = dc.getHeight();
        mKind = Layout.slotKind(mW, mH, Config.read().layout);
    }

    // ---- 데이터 (1Hz) -----------------------------------------------------

    function compute(info) {
        mTick++;
        var cfg = Config.read();

        var h = null;
        if (cfg.gpsHeading && (info has :track) && info.track != null) {
            h = info.track;
        } else if ((info has :currentHeading) && info.currentHeading != null) {
            h = info.currentHeading;
        }
        if (h != null) {
            mHeading = Math.toDegrees(h).toFloat();
        }

        // 1분마다 위치 갱신 (실제 저장은 1km 이동 또는 30분 경과 시에만)
        if (mTick % 60 == 1) {
            LocationStore.capture(false);
        }
    }

    hidden function sun() {
        var day = Time.today().value();
        if (day != mSunDay || mTick - mSunTick >= 300) {
            LocationStore.load();
            mSun = Astro.sunTimes(LocationStore.lat, LocationStore.lng);
            mSunDay = day;
            mSunTick = mTick;
        }
        return mSun;
    }

    // ---- 그리기 -----------------------------------------------------------

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (w != mW || h != mH) {
            onLayout(dc);
        }
        setColors();

        dc.setColor(mClearBg, mClearBg);
        dc.clear();
        // 링/화살표/달 같은 도형 계단 현상 방지 (CIQ 기본값은 꺼짐)
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var mode = currentMode();
        if (mKind == Layout.SLOT_QUAD) {
            var hw = w / 2;
            var hh = h / 2;
            drawPanel(dc, Config.MODE_WIND,     0,  0,  hw,     hh);
            drawPanel(dc, Config.MODE_FORECAST, hw, 0,  w - hw, hh);
            drawPanel(dc, Config.MODE_SUN,      0,  hh, hw,     h - hh);
            drawPanel(dc, Config.MODE_MOON,     hw, hh, w - hw, h - hh);
            dc.setColor(mLine, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(hw, 4, hw, h - 4);
            dc.drawLine(4, hh, w - 4, hh);
        } else if (mKind == Layout.SLOT_DOUBLE) {
            var hw2 = w / 2;
            var right = rightMode(mode);
            drawPanel(dc, Config.MODE_WIND, 0, 0, hw2, h);
            drawPanel(dc, right, hw2, 0, w - hw2, h);
            dc.setColor(mLine, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(hw2, 4, hw2, h - 4);
        } else {
            drawPanel(dc, mode, 0, 0, w, h);
        }
    }

    hidden function setColors() {
        // 배경색 (설정 bgMode) : 0 자동 / 1 검정·흰색 그대로 / 2 투명 (칠하지 않음)
        var cfg = Config.read();
        var bg = getBackgroundColor();
        var big = (System.getDeviceSettings().screenWidth >= 480);   // 1050 / 1060
        var soft = big && (cfg.bgMode != Config.BG_PLAIN);
        var sysClear = (bg == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        mDark = (bg == Graphics.COLOR_BLACK || sysClear);
        if (mDark) {
            mBg = soft ? 0x17181D : Graphics.COLOR_BLACK;
            mFg = Graphics.COLOR_WHITE;
            mDim = Graphics.COLOR_LT_GRAY;
            mLine = Graphics.COLOR_DK_GRAY;
            mAccent = Graphics.COLOR_YELLOW;
        } else {
            mBg = soft ? 0xDCDCDC : Graphics.COLOR_WHITE;   // 1050/1060 의 밝은 배경은 순백이 아니다
            mFg = soft ? 0x313152 : Graphics.COLOR_BLACK;
            mDim = Graphics.COLOR_DK_GRAY;
            mLine = Graphics.COLOR_LT_GRAY;
            mAccent = Graphics.COLOR_ORANGE;
        }
        // 지우기만 투명 (mBg 는 패널 속을 칠할 때 쓰므로 실제 색 유지).
        // 자동 모드에서도 기기가 투명이라고 알려줬으면 칠하지 않는다 - 그게 색이 어긋나던 원인.
        var noFill = (cfg.bgMode == Config.BG_CLEAR)
                  || (cfg.bgMode == Config.BG_AUTO && sysClear);
        mClearBg = noFill ? Graphics.COLOR_TRANSPARENT : mBg;
    }

    hidden function drawPanel(dc, mode, x, y, w, h) {
        if (w < 20 || h < 16) {
            return;
        }
        switch (mode) {
            case Config.MODE_FORECAST: drawForecast(dc, x, y, w, h); break;
            case Config.MODE_SUN:      drawSun(dc, x, y, w, h);      break;
            case Config.MODE_MOON:     drawMoon(dc, x, y, w, h);     break;
            default:                   drawWind(dc, x, y, w, h);
        }
    }

    // ---- 바람 -------------------------------------------------------------
    //  [풍향 링 + 진행방향 화살표]  [풍속 / 단위]
    //  링의 구멍 = 바람이 불어 들어오는 쪽 ("구멍으로 바람이 들어온다").

    hidden function drawWind(dc, x, y, w, h) {
        var cfg = Config.read();
        var pad = padOf(w, h);
        var wind = WeatherData.currentWind();

        var d = min(h - 2 * pad, (w * 0.42).toNumber());
        var arcPen = max(3, (d * 0.15).toNumber());
        var r = (d - arcPen) / 2.0;
        var cx = x + pad + d / 2.0;
        var cy = y + h / 2.0;

        // 링 = 바람. 굵은 링에 "구멍"(약 30도)이 바람이 들어오는 쪽.
        // 링 색: 맞바람 빨강 / 옆바람 회색 / 뒷바람 파랑. 데이터 없으면 구멍 없는 흐린 링.
        dc.setPenWidth(arcPen);
        if (wind != null && wind[0] != null) {
            var from = wind[0].toFloat();
            var rel = norm360(from - mHeading);
            var shown = cfg.trackUp ? rel : from;
            var a = 90.0 - shown;                    // CIQ 각도: 3시=0, 반시계 +
            dc.setColor(relColor(rel), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, a + 15, a + 345);
        } else {
            dc.setColor(mLine, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
        }

        drawNavArrow(dc, cx, cy, r * 0.58, cfg.trackUp ? 0.0 : mHeading, mFg);

        // 풍속 / 단위
        var tx = x + pad + d + max(3, pad);
        var tw = x + w - pad - tx;
        if (tw < 14) {
            return;
        }
        var spd = "--";
        if (wind != null && wind[1] != null) {
            var v = wind[1] * cfg.unitFactor;
            spd = (v >= 10) ? v.format("%d") : v.format("%.1f");
        }
        drawValueStack(dc, tx, y, tw, h, pad, spd, "0.0", 3, cfg.unitLabel, cfg.unitLabel.length() + 1, null);
    }

    hidden function relColor(rel) {
        if (rel < 60 || rel >= 300) {
            return mDark ? Graphics.COLOR_RED : Graphics.COLOR_DK_RED;     // 맞바람
        }
        if (rel >= 150 && rel < 210) {
            return mDark ? Graphics.COLOR_BLUE : Graphics.COLOR_DK_BLUE;   // 뒷바람
        }
        return mDark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;    // 옆바람
    }

    // wind.svg 모양 화살표. deg: 위=0, 시계방향.
    hidden function drawNavArrow(dc, cx, cy, s, deg, color) {
        var rad = deg * Math.PI / 180.0;
        var c = Math.cos(rad);
        var sn = Math.sin(rad);
        var pts = new [4];
        for (var i = 0; i < 4; i++) {
            var px = NAV_X[i] * s;
            var py = NAV_Y[i] * s;
            pts[i] = [cx + px * c - py * sn, cy + px * sn + py * c];
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // ---- 시간별 예보 -------------------------------------------------------
    //  [날씨 아이콘]  [시각 / ↗ 강수확률%]   2초마다 다음 시간으로 넘어감 (최대 12시간)

    hidden function drawForecast(dc, x, y, w, h) {
        var cfg = Config.read();
        var pad = padOf(w, h);
        var n = WeatherData.forecastCount();
        var f = null;
        if (n > 0) {
            f = WeatherData.forecast((mTick / 2) % min(n, 12));
        }

        var icon = "Z";
        var hourStr = "--";
        var sub = null;
        var toward = null;
        if (f != null) {
            var sec = WeatherData.secOfDay(f[0]);
            var s = sun();
            var night;
            if (s != null) {
                night = (sec < s[0] || sec > s[1]);
            } else {
                night = (sec < 6 * 3600 || sec > 18 * 3600);
            }
            icon = WeatherData.iconChar(f[1], night);
            hourStr = fmtHour(sec / 3600, cfg.use24h);
            if (f[2] != null) {
                sub = f[2].format("%d") + "%";
            }
            toward = f[3];
        }

        var wi = Layout.fitWx(((w - 2 * pad) * 0.5).toNumber(), h - 2 * pad);
        var wf = wxFont(wi);
        // 아이콘 칸은 가장 넓은 아이콘 폭으로 고정 -> 날씨가 바뀌어도 오른쪽 글자 크기 그대로
        var boxW = Layout.WX_ADV[wi];
        dc.setColor(mAccent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad + boxW / 2, y + (h - Layout.WX_CAP[wi]) / 2, wf, icon, Graphics.TEXT_JUSTIFY_CENTER);

        var tx = x + pad + boxW + max(3, pad);
        var tw = x + w - pad - tx;
        if (tw < 14) {
            return;
        }
        // 글자 수와 상관없이 같은 크기: 시각은 "23"/"11p", 아래 줄은 화살표 + "100%" 자리 확보
        drawValueStack(dc, tx, y, tw, h, pad, hourStr, cfg.use24h ? "00" : "00p", cfg.use24h ? 2 : 3, sub, 6.4, toward);
    }

    // ---- 일출 / 일몰 --------------------------------------------------------
    //  위아래 2줄(또는 칸이 납작하면 좌우 2칸). 이미 지난 시각은 흐리게.

    hidden function drawSun(dc, x, y, w, h) {
        var cfg = Config.read();
        var pad = padOf(w, h);
        var s = sun();
        var riseStr = "--:--";
        var setStr = "--:--";
        var riseDim = false;
        var setDim = false;
        if (s != null) {
            riseStr = fmtTime(s[0], cfg.use24h);
            setStr = fmtTime(s[1], cfg.use24h);
            var now = WeatherData.secOfDay(Time.now());
            riseDim = now > s[0];
            setDim = now > s[1];
        }
        var len = cfg.use24h ? 5 : 6;     // "17:20" / "12:59p" 기준으로 고정 (날마다 크기 안 바뀌게)
        var innerW = w - 2 * pad;
        var innerH = h - 2 * pad;

        // A) 위아래
        var rowH = innerH / 2;
        var aWi = Layout.fitWx((innerW * 0.38).toNumber(), rowH);
        var ref = cfg.use24h ? "00:00" : "00:00p";
        var aTi = capMain(dc, ref, innerW - Layout.WX_ADV[aWi] - pad, (rowH * 0.8).toNumber(), len);
        // B) 좌우
        var colW = (innerW - pad) / 2;
        var bWi = Layout.fitWx((colW * 0.42).toNumber(), innerH);
        var bTi = capMain(dc, ref, colW - Layout.WX_ADV[bWi] - 2, (innerH * 0.6).toNumber(), len);

        if (Layout.TW_CAP[aTi] >= Layout.TW_CAP[bTi]) {
            drawSunRow(dc, x + pad, y + pad, innerW, rowH, aWi, aTi, "G", riseStr, riseDim);
            drawSunRow(dc, x + pad, y + pad + rowH, innerW, innerH - rowH, aWi, aTi, "g", setStr, setDim);
        } else {
            drawSunRow(dc, x + pad, y + pad, colW, innerH, bWi, bTi, "G", riseStr, riseDim);
            drawSunRow(dc, x + pad + colW + pad, y + pad, colW, innerH, bWi, bTi, "g", setStr, setDim);
        }
    }

    hidden function drawSunRow(dc, x, y, w, h, wi, ti, icon, text, dim) {
        var wf = wxFont(wi);
        var tf = twFont(ti);
        var iw = dc.getTextWidthInPixels(icon, wf);
        var textW = dc.getTextWidthInPixels(text, tf);
        var gap = max(2, Layout.TW_CAP[ti] / 4);
        var total = iw + gap + textW;
        var x0 = x + (w - total) / 2;
        if (x0 < x) { x0 = x; }
        dc.setColor(dim ? mDim : mAccent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, y + (h - Layout.WX_CAP[wi]) / 2, wf, icon, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(dim ? mDim : mFg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + iw + gap, y + (h - Layout.TW_CAP[ti]) / 2, tf, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ---- 달 ---------------------------------------------------------------
    //  [달 모양(실제 위상으로 그림)]  [밝기% / 월령d]

    hidden function drawMoon(dc, x, y, w, h) {
        var pad = padOf(w, h);
        var m = Astro.moon(Time.now().value());
        var el = m[0];
        var illum = m[1];
        var age = m[2];

        var d = min(h - 2 * pad, (w * 0.42).toNumber());
        var r = d / 2.0 - 1;
        var cx = x + pad + d / 2.0;
        var cy = y + h / 2.0;
        var south = (LocationStore.lat != null && LocationStore.lat < 0);
        drawMoonDisk(dc, cx, cy, r, el, south);

        var tx = x + pad + d + max(3, pad);
        var tw = x + w - pad - tx;
        if (tw < 14) {
            return;
        }
        var pct = (illum + 0.5).toNumber();
        if (pct > 100) { pct = 100; }
        drawValueStack(dc, tx, y, tw, h, pad, pct.format("%d") + "%", "100%", 4, age.format("%.1f") + "d", 6, null);
    }

    // el: 이각(0=삭, 180=망). 북반구는 차오를 때 오른쪽이 밝다.
    hidden function drawMoonDisk(dc, cx, cy, r, el, south) {
        dc.setColor(mDark ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);

        var k = Math.cos(el * Math.PI / 180.0);
        if (k > 0.995) {
            return;                       // 삭 - 밝은 부분 없음
        }
        var side = (el < 180) ? 1 : -1;
        if (south) { side = -side; }

        var steps = 12;
        var pts = new [steps * 2 + 2];
        var n = 0;
        for (var i = 0; i <= steps; i++) {
            var t = -Math.PI / 2 + Math.PI * i / steps;
            pts[n] = [cx + side * r * Math.cos(t), cy + r * Math.sin(t)];
            n++;
        }
        for (var j = steps; j >= 0; j--) {
            var t2 = -Math.PI / 2 + Math.PI * j / steps;
            pts[n] = [cx + side * k * r * Math.cos(t2), cy + r * Math.sin(t2)];
            n++;
        }
        dc.setColor(mAccent, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // ---- 공통: 오른쪽 텍스트 영역 (큰 값 + 아래 작은 줄) -----------------------
    //  mainSlots/subSlots: 글자 수 대신 쓰는 "확보할 칸 수". 값이 바뀌어도
    //  ("1p" -> "11p", "4.6" -> "12", "56%" -> "100%") 폰트 크기가 흔들리지 않게 한다.
    //  subSlots > 0 이면 아래 줄 자리를 항상 확보 (값이 null 이어도 위 숫자 크기 유지).
    //  arrowDeg != null 이면 아래 줄 앞에 작은 방향 화살표.

    hidden function drawValueStack(dc, tx, y, tw, h, pad, main, ref, mainSlots, sub, subSlots, arrowDeg) {
        var avail = h - 2 * pad;
        var hasSub = (subSlots > 0);
        var mi = capMain(dc, ref, tw, (avail * (hasSub ? 0.6 : 0.85)).toNumber(), mainSlots + 0.2);
        var si = 0;
        var subW = 0;
        var arrowS = 0;
        var gapV = 0;
        if (hasSub) {
            si = Layout.fitTw(tw, (avail * 0.3).toNumber(), subSlots);
            while (si > 0 && Layout.TW_CAP[si] > Layout.TW_CAP[mi] * 0.7) { si--; }
            gapV = max(2, Layout.TW_CAP[si] / 2);
        }
        var totalH = Layout.TW_CAP[mi] + (hasSub ? gapV + Layout.TW_CAP[si] : 0);
        var top = y + (h - totalH) / 2;
        var cxT = tx + tw / 2;

        dc.setColor(mFg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cxT, top, twFont(mi), main, Graphics.TEXT_JUSTIFY_CENTER);

        if (hasSub && (sub != null || arrowDeg != null)) {
            var sy = top + Layout.TW_CAP[mi] + gapV;
            var sf = twFont(si);
            if (sub != null) {
                subW = dc.getTextWidthInPixels(sub, sf);
            }
            if (arrowDeg != null) {
                arrowS = Layout.TW_CAP[si] / 2.0;
            }
            var arrowGap = (arrowDeg != null && sub != null) ? max(2, (arrowS / 2).toNumber()) : 0;
            var total = (arrowS * 2) + arrowGap + subW;
            var x0 = cxT - total / 2;
            if (arrowDeg != null) {
                drawNavArrow(dc, x0 + arrowS, sy + arrowS, arrowS, arrowDeg, mDim);
            }
            if (sub != null) {
                dc.setColor(mDim, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x0 + arrowS * 2 + arrowGap, sy, sf, sub, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }

    // 숫자는 다른 zz+ 앱 "두번째 항목" 크기로 통일 (ref = 가장 넓은 값의 실제 폭으로 판단).
    // 칸이 좁아 안 들어가면 예전처럼 들어가는 가장 큰 크기.
    hidden function capMain(dc, ref, maxW, maxH, nChars) {
        var s = Layout.subTw();
        var refW = dc.getTextWidthInPixels(ref, twFont(s));
        if (Layout.TW_CAP[s] <= maxH && refW <= maxW) {
            return s;
        }
        // 실제 폭 기준 칸 수 (예: "100%" 는 4칸이 아니라 약 3.4칸) -> 사다리에서 고름
        var slots = refW.toFloat() / Layout.TW_ADV[s];
        if (slots > nChars) { slots = nChars; }
        return Layout.fitTw(maxW, maxH, slots);
    }

    // ---- 폰트 ---------------------------------------------------------------

    hidden function twFont(i) {
        if (i < 0) { i = 0; }
        if (i >= Layout.TW_ALL) { i = Layout.TW_ALL - 1; }
        if (mTwCache[i] == null) {
            mTwCache[i] = WatchUi.loadResource(twRez(i));
        }
        return mTwCache[i];
    }

    hidden function wxFont(i) {
        if (i < 0) { i = 0; }
        if (i >= Layout.WX_N) { i = Layout.WX_N - 1; }
        if (mWxCache[i] == null) {
            mWxCache[i] = WatchUi.loadResource(wxRez(i));
        }
        return mWxCache[i];
    }

    hidden function twRez(i) {
        switch (i) {
            case 0:  return Rez.Fonts.Tw16;
            case 1:  return Rez.Fonts.Tw20;
            case 2:  return Rez.Fonts.Tw24;
            case 3:  return Rez.Fonts.Tw30;
            case 4:  return Rez.Fonts.Tw38;
            case 5:  return Rez.Fonts.Tw48;
            case 6:  return Rez.Fonts.Tw60;
            case 7:  return Rez.Fonts.Tw76;
            case 8:  return Rez.Fonts.Tw96;
            case 10: return Rez.Fonts.TwS20;
            case 11: return Rez.Fonts.TwS24;
            case 12: return Rez.Fonts.TwS36;
            case 13: return Rez.Fonts.TwS41;
            default: return Rez.Fonts.Tw120;
        }
    }

    hidden function wxRez(i) {
        switch (i) {
            case 0:  return Rez.Fonts.Wx20;
            case 1:  return Rez.Fonts.Wx26;
            case 2:  return Rez.Fonts.Wx32;
            case 3:  return Rez.Fonts.Wx40;
            case 4:  return Rez.Fonts.Wx52;
            case 5:  return Rez.Fonts.Wx64;
            case 6:  return Rez.Fonts.Wx80;
            default: return Rez.Fonts.Wx100;
        }
    }

    // ---- helpers ------------------------------------------------------------

    hidden function fmtTime(sec, use24h) {
        sec = sec.toNumber() % 86400;
        if (sec < 0) { sec += 86400; }
        var hh = sec / 3600;
        var mm = (sec % 3600) / 60;
        if (use24h) {
            return hh.format("%d") + ":" + mm.format("%02d");
        }
        var suffix = (hh >= 12) ? "p" : "a";
        var h12 = hh % 12;
        if (h12 == 0) { h12 = 12; }
        return h12.format("%d") + ":" + mm.format("%02d") + suffix;
    }

    hidden function fmtHour(hh, use24h) {
        if (use24h) {
            return hh.format("%02d");
        }
        var suffix = (hh >= 12) ? "p" : "a";
        var h12 = hh % 12;
        if (h12 == 0) { h12 = 12; }
        return h12.format("%d") + suffix;
    }

    hidden function padOf(w, h) {
        var p = (min(w, h) * 0.06).toNumber();
        return (p < 2) ? 2 : p;
    }

    hidden function norm360(a) {
        while (a < 0) { a += 360; }
        while (a >= 360) { a -= 360; }
        return a;
    }

    hidden function min(a, b) { return (a < b) ? a : b; }
    hidden function max(a, b) { return (a > b) ? a : b; }
}
