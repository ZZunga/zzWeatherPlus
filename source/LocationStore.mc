using Toybox.Activity;
using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;
using Toybox.Weather;

// 마지막으로 확인된 위치를 기기에 저장/복원한다.
//
// 기존 zzWeather 문제: 위치를 못 읽으면(실내 시작, GPS 미수신, 첫 설치 직후)
// 일출/일몰 계산이 null 로 죽었고, "설정을 한 번 저장"하면 Properties 의
// LastLocationLat/Lng 가 다시 채워지면서 살아났다.
//
// 개선:
//   1) 앱이 켜지는 순간(App.onStart / View.initialize) capture() 로 위치를 읽어 즉시 저장
//   2) 활동 중에도 주기적으로 갱신 (1km 이상 이동 or 30분 경과 시에만 쓰기)
//   3) 읽기 우선순위: 실시간 GPS > Position 마지막 위치 > 폰 날씨 관측 위치
//      > Storage 저장값 > Properties 저장값 > 기본값(서울)
//   4) 저장은 Application.Storage 에만 (기기 안에만 남고, 설정 동기화로 폰에 올라가거나
//      덮어써지지 않음). Properties 의 LastLocationLat/Lng 는 읽기 전용 기본값.
//
// 따라서 위치 값이 null 이 되는 경로가 없다.
module LocationStore {

    const DEFAULT_LAT = 37.57842345603164d;
    const DEFAULT_LNG = 126.97692630949079d;
    const KEY = "lastLoc";

    const SAVE_MIN_MOVE_DEG = 0.01d;   // 약 1km
    const SAVE_MIN_INTERVAL = 1800;    // 30분

    var lat = null;
    var lng = null;
    var isLive = false;           // 이번 실행에서 실제 위치를 한 번이라도 읽었는가
    var _savedLat = null;
    var _savedLng = null;
    var _lastSaveSec = 0;

    function valid(la, lo) {
        if (la == null || lo == null) {
            return false;
        }
        if (la > 89.9d || la < -89.9d || lo > 180.0d || lo < -180.0d) {
            return false;          // 180,180(라디안 pi) 같은 무효 표시값 포함
        }
        if (la < 0.0001d && la > -0.0001d && lo < 0.0001d && lo > -0.0001d) {
            return false;          // 0,0 = 미수신
        }
        return true;
    }

    // 저장된 값 복원. 실패해도 기본값으로 채운다.
    function load() {
        if (lat != null && lng != null) {
            return;
        }
        try {
            var v = Storage.getValue(KEY);
            if (v instanceof Lang.Array && v.size() >= 2 && valid(v[0], v[1])) {
                _set(v[0], v[1]);
                _savedLat = lat;
                _savedLng = lng;
                return;
            }
        } catch (ex) {
        }
        try {
            var la = Properties.getValue("LastLocationLat");
            var lo = Properties.getValue("LastLocationLng");
            if (valid(la, lo)) {
                _set(la, lo);
                return;
            }
        } catch (ex) {
        }
        _set(DEFAULT_LAT, DEFAULT_LNG);
    }

    // 지금 읽을 수 있는 위치를 찾아 갱신. force=true 면 이동량/시간과 무관하게 바로 저장.
    // 위치를 얻었으면 true.
    function capture(force) {
        load();
        var deg = _readNow();
        if (deg == null) {
            return false;
        }
        _set(deg[0], deg[1]);
        isLive = true;
        _maybeSave(force);
        return true;
    }

    // 활동 종료/리셋 시 호출: 마지막 위치를 확실히 남긴다.
    function flush() {
        if (isLive) {
            _maybeSave(true);
        }
    }

    // ---- 내부 ---------------------------------------------------------

    function _set(la, lo) {
        lat = la.toDouble();
        lng = lo.toDouble();
    }

    function _readNow() {
        // 1) 활동 중 실시간 위치
        try {
            var ai = Activity.getActivityInfo();
            if (ai != null && (ai has :currentLocation) && ai.currentLocation != null) {
                var d = ai.currentLocation.toDegrees();
                if (valid(d[0], d[1])) {
                    return d;
                }
            }
        } catch (ex) {
        }
        // 2) Position 의 현재/마지막 위치 (QUALITY_LAST_KNOWN 이상)
        try {
            var pinfo = Position.getInfo();
            if (pinfo != null && pinfo.position != null && pinfo.accuracy != null
                    && pinfo.accuracy >= Position.QUALITY_LAST_KNOWN) {
                var d2 = pinfo.position.toDegrees();
                if (valid(d2[0], d2[1])) {
                    return d2;
                }
            }
        } catch (ex) {
        }
        // 3) 폰에서 받은 날씨 관측 위치 (GPS 없이도 대략적인 위치)
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && (cc has :observationLocationPosition)
                        && cc.observationLocationPosition != null) {
                    var d3 = cc.observationLocationPosition.toDegrees();
                    if (valid(d3[0], d3[1])) {
                        return d3;
                    }
                }
            }
        } catch (ex) {
        }
        return null;
    }

    function _maybeSave(force) {
        var now = Time.now().value();
        if (!force) {
            var moved = true;
            if (_savedLat != null && _savedLng != null) {
                var dLa = lat - _savedLat;
                var dLo = lng - _savedLng;
                if (dLa < 0) { dLa = -dLa; }
                if (dLo < 0) { dLo = -dLo; }
                moved = (dLa > SAVE_MIN_MOVE_DEG || dLo > SAVE_MIN_MOVE_DEG);
            }
            if (!moved && (now - _lastSaveSec) < SAVE_MIN_INTERVAL) {
                return;
            }
        }
        try {
            Storage.setValue(KEY, [lat, lng]);
        } catch (ex) {
        }
        _savedLat = lat;
        _savedLng = lng;
        _lastSaveSec = now;
    }
}
