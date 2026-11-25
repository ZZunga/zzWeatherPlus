using Toybox.Math;
using Toybox.Position;
using Toybox.Time;
using Toybox.Weather;
using Toybox.Lang;

// 일출/일몰, 달 위상 계산.
//
// 일출/일몰: Weather.getSunrise/getSunset 을 먼저 쓰고, 없거나(null/예외) 실패하면
// 자체 계산(NOAA 일출 방정식, 오차 ±1~2분)으로 대체한다. 기존 zzWeather 가
// Weather API 가 없는 기기/상황에서 null Moment 를 Gregorian.info() 에 넘겨 죽던
// 문제를 원천 차단한다.
//
// 달: 태양·달 황경 근사식(달 이심 보정 포함)으로 이각(elongation)을 구해
// 조명률(%)과 차고/기욺을 계산한다. 음력표(2021~2100) 범위 밖/경계에서
// 인덱스 오류가 나던 문제도 같이 사라진다.
module Astro {

    const RAD = 0.017453292519943295d;
    const SYNODIC = 29.530588853d;

    function _mod360(x) {
        return x - 360.0d * Math.floor(x / 360.0d);
    }

    // 결과: [일출초, 일몰초] (오늘 로컬 자정 기준 초) 또는 null(백야/극야/위치 없음)
    function sunTimes(lat, lng) {
        if (lat == null || lng == null) {
            return null;
        }
        var today = Time.today();
        var res = _sunFromWeather(lat, lng, today);
        if (res == null) {
            res = _sunCalc(lat.toDouble(), lng.toDouble(), today.value().toDouble());
        }
        return res;
    }

    function _sunFromWeather(lat, lng, today) {
        if (!(Toybox has :Weather) || !(Weather has :getSunrise) || !(Weather has :getSunset)) {
            return null;
        }
        try {
            var loc = new Position.Location({
                :latitude => lat.toDouble(),
                :longitude => lng.toDouble(),
                :format => :degrees
            });
            var r = Weather.getSunrise(loc, today);
            var s = Weather.getSunset(loc, today);
            if (r == null || s == null) {
                return null;
            }
            var t0 = today.value();
            return [r.value() - t0, s.value() - t0];
        } catch (ex) {
            return null;
        }
    }

    // NOAA sunrise equation. todaySec = 로컬 자정의 Unix 초.
    function _sunCalc(lat, lng, todaySec) {
        var jd = (todaySec + 43200.0d) / 86400.0d + 2440587.5d;
        var n = Math.floor(jd - 2451545.0d + 0.5d).toDouble();
        var j = n - lng / 360.0d;
        var m = _mod360(357.5291d + 0.98560028d * j);
        var c = 1.9148d * Math.sin(m * RAD) + 0.02d * Math.sin(2.0d * m * RAD)
              + 0.0003d * Math.sin(3.0d * m * RAD);
        var l = _mod360(m + c + 180.0d + 102.9372d);
        var jt = 2451545.0d + j + 0.0053d * Math.sin(m * RAD) - 0.0069d * Math.sin(2.0d * l * RAD);
        var sd = Math.sin(l * RAD) * Math.sin(23.4397d * RAD);
        var cd = Math.cos(Math.asin(sd));
        var cw = (Math.sin(-0.833d * RAD) - Math.sin(lat * RAD) * sd) / (Math.cos(lat * RAD) * cd);
        if (cw < -1.0d || cw > 1.0d) {
            return null;
        }
        var w = Math.acos(cw) / RAD / 360.0d;
        var rise = (jt - w - 2440587.5d) * 86400.0d - todaySec;
        var set  = (jt + w - 2440587.5d) * 86400.0d - todaySec;
        return [rise.toNumber(), set.toNumber()];
    }

    // 결과: [이각(0~360, 0=삭 180=망), 조명률(0~100), 월령(일)]
    function moon(unixSec) {
        var d = unixSec.toDouble() / 86400.0d + 2440587.5d - 2451545.0d;
        var lm = 218.316d + 13.176396d * d;
        var mm = 134.963d + 13.064993d * d;
        lm = lm + 6.289d * Math.sin(_mod360(mm) * RAD);
        var g = _mod360(357.529d + 0.98560028d * d);
        var q = 280.459d + 0.98564736d * d;
        var ls = q + 1.915d * Math.sin(g * RAD) + 0.020d * Math.sin(2.0d * g * RAD);
        var el = _mod360(lm - ls);
        var illum = (1.0d - Math.cos(el * RAD)) / 2.0d * 100.0d;
        var age = el / 360.0d * SYNODIC;
        return [el, illum, age];
    }
}
