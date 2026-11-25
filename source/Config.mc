using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.System;

// 설정 스냅샷 + 캐싱. Properties 읽기는 전부 try/catch + 기본값.
// (기존 앱은 getValue 결과를 그대로 써서, 값이 비면 바로 크래시했다)
module Config {

    // 배경색 (bgMode)
    enum {
        BG_AUTO  = 0,   // 기기 화면과 같은 색으로 칠함 (1050/1060 은 #17181D / 남색 글씨)
        BG_PLAIN = 1,   // 기기가 알려준 검정 / 흰색 그대로
        BG_CLEAR = 2    // 칠하지 않음 (기기 배경이 그대로 비침)
    }

    // 표시 항목 (dataType)
    enum {
        MODE_WIND     = 0,
        MODE_FORECAST = 1,
        MODE_SUN      = 2,
        MODE_MOON     = 3
    }
    const NMODES = 4;

    // 풍속 단위 (windSpeedUnit)
    enum {
        UNIT_KPH = 0,
        UNIT_MPH = 1,
        UNIT_MPS = 2,
        UNIT_FPS = 3
    }

    // 칸 배치 (layoutMode)
    enum {
        LAYOUT_AUTO   = 0,   // 칸 크기에 따라 1/2/4 패널
        LAYOUT_SINGLE = 1    // 항상 선택 항목 하나만 크게
    }

    // 시간 표시 (timeFormat)
    enum {
        TIME_DEVICE = 0,
        TIME_12H    = 1,
        TIME_24H    = 2
    }

    class Snapshot {
        var bgMode     = BG_PLAIN; // 배경색
        var mode       = MODE_WIND;
        var trackUp    = true;    // 진행방향을 위로 (false = 북쪽 위)
        var gpsHeading = true;    // GPS 진행방향 사용 (false = 나침반)
        var windUnit   = UNIT_MPS;
        var touch      = true;
        var use24h     = true;
        var layout     = LAYOUT_AUTO;

        var unitLabel  = "m/s";
        var unitFactor = 1.0;     // m/s -> 표시 단위
    }

    var _cache = null;

    function invalidate() {
        _cache = null;
    }

    function _get(key, dflt) {
        try {
            var v = Properties.getValue(key);
            if (v != null) {
                return v;
            }
        } catch (ex) {
        }
        return dflt;
    }

    function read() {
        if (_cache != null) {
            return _cache;
        }
        var s = new Snapshot();
        s.mode       = _clamp(_get("dataType", MODE_WIND), 0, NMODES - 1);
        s.trackUp    = _get("northOrientation", true);
        s.gpsHeading = _get("showGpsOrientation", true);
        s.windUnit   = _clamp(_get("windSpeedUnit", UNIT_MPS), 0, 3);
        s.touch      = _get("touchScreen", true);
        s.layout     = _clamp(_get("layoutMode", LAYOUT_AUTO), 0, 1);

        var tf = _clamp(_get("timeFormat", TIME_DEVICE), 0, 2);
        if (tf == TIME_DEVICE) {
            var ds = System.getDeviceSettings();
            s.use24h = (ds has :is24Hour) ? ds.is24Hour : true;
        } else {
            s.use24h = (tf == TIME_24H);
        }

        switch (s.windUnit) {
            case UNIT_KPH: s.unitLabel = "km/h"; s.unitFactor = 3.6;     break;
            case UNIT_MPH: s.unitLabel = "mph";  s.unitFactor = 2.23694; break;
            case UNIT_FPS: s.unitLabel = "ft/s"; s.unitFactor = 3.28084; break;
            default:       s.unitLabel = "m/s";  s.unitFactor = 1.0;
        }
        s.bgMode     = _clamp(_get("bgMode", BG_PLAIN), 0, 2);
        _cache = s;
        return s;
    }

    function _clamp(v, lo, hi) {
        if (!(v instanceof Lang.Number)) {
            return lo;
        }
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }
}
