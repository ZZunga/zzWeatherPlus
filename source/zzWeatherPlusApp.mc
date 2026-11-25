using Toybox.Application;
using Toybox.WatchUi;

// 앱 진입점. manifest.xml 의 entry="zzWeatherPlusApp" 와 일치해야 한다.
class zzWeatherPlusApp extends Application.AppBase {

    hidden var mView = null;

    function initialize() {
        AppBase.initialize();
    }

    // 앱이 켜지는 순간: 저장된 위치를 복원하고, 지금 읽을 수 있는 위치가 있으면
    // 바로 저장한다. (기존 앱에서 "설정 한 번 저장"으로 해결되던 위치 누락 크래시 대응)
    function onStart(state) {
        LocationStore.load();
        LocationStore.capture(true);
    }

    function onStop(state) {
        LocationStore.flush();
    }

    function getInitialView() {
        mView = new zzWeatherPlusView();
        return [ mView, new zzWeatherPlusDelegate(mView) ];
    }

    // Connect IQ 앱 / Garmin Express 에서 설정 변경 시
    function onSettingsChanged() {
        Config.invalidate();
        if (mView != null) {
            mView.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}
