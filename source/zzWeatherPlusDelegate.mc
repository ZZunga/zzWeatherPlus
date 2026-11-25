using Toybox.WatchUi;

// 터치: 칸을 탭하면 표시 항목(바람 > 예보 > 일출일몰 > 달) 순환.
// 설정 "터치스크린 사용" 이 꺼져 있으면 탭을 기기에 그대로 넘긴다.
class zzWeatherPlusDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onTap(clickEvent) {
        if (mView == null) {
            return false;
        }
        return mView.nextMode();
    }
}
