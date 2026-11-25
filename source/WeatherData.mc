using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Weather;

// Weather API 래퍼. 모든 필드를 null 체크한다.
// (기존 앱: cc.windBearing.toFloat() / hf.windBearing + 180 / hf.temperature * 1.8
//  에서 값이 null 이면 크래시)
module WeatherData {

    // 현재 바람: [불어오는 방향(도, 북=0 시계방향), 풍속(m/s)] 또는 null
    //  1) 현재 관측값 (CurrentConditions)
    //  2) 없으면 시간별 예보 중 지금 시각에 가장 가까운 것 (2시간 이내)
    //  3) 그래도 없으면 마지막으로 받은 값 (1시간 이내)
    //  폰 연결이 잠깐 끊기거나 시뮬레이터에서 설정을 저장해 앱이 다시 시작되면
    //  현재 관측값이 비는 경우가 있어서, 바로 "--" 가 되지 않게 한다.
    var _lastWind = null;
    var _lastWindAt = 0;

    function currentWind() {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var now = Time.now().value();
        var w = _windNow();
        if (w == null) {
            w = _windFromForecast(now);
        }
        if (w != null) {
            _lastWind = w;
            _lastWindAt = now;
            return w;
        }
        if (_lastWind != null && now - _lastWindAt < 3600) {
            return _lastWind;
        }
        return null;
    }

    function _windNow() {
        try {
            var cc = Weather.getCurrentConditions();
            if (cc == null) {
                return null;
            }
            var b = cc.windBearing;
            var s = cc.windSpeed;
            if (b == null && s == null) {
                return null;
            }
            return [b, s];
        } catch (ex) {
            return null;
        }
    }

    function _windFromForecast(now) {
        try {
            var hf = Weather.getHourlyForecast();
            if (hf == null) {
                return null;
            }
            var best = null;
            var bestD = 7200;                       // 2시간 넘게 떨어진 예보는 쓰지 않음
            for (var i = 0; i < hf.size(); i++) {
                var f = hf[i];
                if (f == null || f.forecastTime == null || (f.windBearing == null && f.windSpeed == null)) {
                    continue;
                }
                var d = f.forecastTime.value() - now;
                if (d < 0) { d = -d; }
                if (d < bestD) {
                    bestD = d;
                    best = [f.windBearing, f.windSpeed];
                }
            }
            return best;
        } catch (ex) {
            return null;
        }
    }

    // 시간별 예보 중 idx 번째: [시각 Moment, 상태코드, 강수확률%, 바람 향하는 방향(도)]
    // 예보가 없으면 null. count 는 forecastCount() 로.
    function forecastCount() {
        if (!(Toybox has :Weather)) {
            return 0;
        }
        try {
            var hf = Weather.getHourlyForecast();
            return (hf == null) ? 0 : hf.size();
        } catch (ex) {
            return 0;
        }
    }

    function forecast(idx) {
        if (!(Toybox has :Weather)) {
            return null;
        }
        try {
            var hf = Weather.getHourlyForecast();
            if (hf == null || hf.size() == 0) {
                return null;
            }
            if (idx < 0 || idx >= hf.size()) {
                idx = 0;
            }
            var f = hf[idx];
            if (f == null || f.forecastTime == null) {
                return null;
            }
            var toward = null;
            if (f.windBearing != null) {
                toward = f.windBearing + 180;
                if (toward >= 360) { toward -= 360; }
            }
            return [f.forecastTime, f.condition, f.precipitationChance, toward];
        } catch (ex) {
            return null;
        }
    }

    // Weather.CONDITION_* -> wx 폰트 문자 (대문자=낮, 소문자=밤, Z=모름)
    function iconChar(cond, night) {
        var c = "R";
        if (cond == null) {
            return "Z";
        }
        switch (cond) {
            case 53:                                  // unknown
                return "Z";
            case 0: case 22: case 23: case 40:        // clear, partly/mostly clear, fair
                c = "A"; break;
            case 1: case 2: case 20: case 52:         // cloudy 류
                c = "C"; break;
            case 8: case 9: case 29: case 30: case 31:
            case 32: case 33: case 35: case 38: case 39:
                c = "F"; break;                       // fog, haze, mist, dust, drizzle...
            case 7: case 10: case 18: case 19: case 21:
            case 44: case 47: case 49: case 50:
                c = "H"; break;                       // rain/snow mix, hail, sleet
            case 4: case 16: case 17: case 34: case 43:
            case 46: case 48: case 51:
                c = "E"; break;                       // snow
            case 6: case 12: case 28: case 41: case 42:
                c = "S"; break;                       // thunder, storm
            case 5: case 36: case 37:
                c = "B"; break;                       // windy, squall
            default:
                c = "R";                              // rain 류
        }
        return night ? c.toLower() : c;
    }

    // Moment -> 로컬 자정 기준 초
    function secOfDay(moment) {
        var i = Gregorian.info(moment, Time.FORMAT_SHORT);
        return i.hour * 3600 + i.min * 60 + i.sec;
    }

    function hourOf(moment) {
        return Gregorian.info(moment, Time.FORMAT_SHORT).hour;
    }
}
