using Toybox.System;

// 비트맵 폰트 표 + 칸(슬롯) 분류.
//
// 폰트는 tools/FntGen.java 로 생성 (README 참고). 재생성하면 아래 표를
// 생성기 출력(px adv cap)으로 맞춘다.
//   tw-*  : Titillium Web Bold, " %-./0123456789:afhkmpst"
//           drawText(x, y) 하면 숫자 윗선이 y 에 온다. CAP = 숫자 높이.
//   wx-*  : Weather Icons, A~Z 로 리매핑. drawText(x, y) 하면 아이콘 박스 위가 y.
//           ADV = 가장 넓은 아이콘 폭, CAP = 가장 높은 아이콘 높이.
module Layout {

    // 0~9: 크기 사다리 (fitTw 가 고름)
    // 10~13: 다른 zz+ 앱의 "두번째 항목" 글자 크기 (tw-s20/24/36/41, 숫자 높이 = 이름)
    const TW_PX  = [ 16, 20, 24, 30, 38, 48, 60, 76, 96, 120, 29, 34, 50, 58 ];
    const TW_ADV = [  9, 11, 13, 17, 21, 27, 34, 43, 54,  67, 16, 19, 28, 32 ];
    const TW_CAP = [ 12, 15, 18, 22, 27, 34, 42, 53, 67,  83, 20, 24, 36, 41 ];
    const TW_N = 10;
    const TW_ALL = 14;

    const WX_PX  = [ 20, 26, 32, 40, 52,  64,  80, 100 ];
    const WX_ADV = [ 32, 41, 51, 64, 83, 102, 128, 159 ];
    const WX_CAP = [ 29, 38, 46, 57, 74,  91, 114, 142 ];
    const WX_N = 8;

    // 칸 배치
    enum {
        SLOT_SINGLE = 0,   // 선택 항목 1개
        SLOT_DOUBLE = 1,   // 좌: 바람 / 우: 선택 항목
        SLOT_QUAD   = 2    // 2x2: 바람, 예보 / 일출일몰, 달
    }

    // 기기 배율: 540/550/840/850 = 246px 기준 1.0, 1040 = 1.15, 1050/1060 = 1.95
    function scale() {
        var w = System.getDeviceSettings().screenWidth;
        if (w == null || w <= 0) {
            return 1.0;
        }
        return w / 246.0;
    }

    //  540  : 246x322 전체, 246x160/129 -> QUAD, 246x106/79/64 -> DOUBLE, 122x66 -> SINGLE
    //  1040 : 282x470/234/155 -> QUAD, 282x116/93 -> DOUBLE, 140x93 -> SINGLE
    //  1050 : 480x800/399/266 -> QUAD, 480x200/160 -> DOUBLE, 239x160 -> SINGLE
    function slotKind(w, h, layoutMode) {
        if (layoutMode == 1) {
            return SLOT_SINGLE;
        }
        var s = scale();
        if (w < 200 * s) {
            return SLOT_SINGLE;
        }
        if (h >= 120 * s) {
            return SLOT_QUAD;
        }
        return SLOT_DOUBLE;
    }

    // maxW 안에 nChars 글자, maxH 안에 들어가는 가장 큰 tw 폰트 인덱스
    function fitTw(maxW, maxH, nChars) {
        var idx = 0;
        for (var i = 0; i < TW_N; i++) {
            if (TW_ADV[i] * nChars <= maxW && TW_CAP[i] <= maxH) {
                idx = i;
            } else {
                break;
            }
        }
        return idx;
    }

    // 기기별 "두번째 항목" 폰트: 246(540/840)=20, 282(1040)=24, 420(550/850)=36, 480(1050/1060)=41
    function subTw() {
        var w = System.getDeviceSettings().screenWidth;
        if (w == null) { return 10; }
        if (w >= 470) { return 13; }
        if (w >= 400) { return 12; }
        if (w >= 270) { return 11; }
        return 10;
    }

    // 숫자는 "두번째 항목" 크기로 통일. 칸이 작아 안 들어가면 fitTw 결과(더 작은 크기).
    function capTw(maxW, maxH, nChars) {
        var s = subTw();
        if (TW_ADV[s] * nChars <= maxW && TW_CAP[s] <= maxH) {
            return s;
        }
        return fitTw(maxW, maxH, nChars);
    }

    function fitWx(maxW, maxH) {
        var idx = 0;
        for (var i = 0; i < WX_N; i++) {
            if (WX_ADV[i] <= maxW && WX_CAP[i] <= maxH) {
                idx = i;
            } else {
                break;
            }
        }
        return idx;
    }
}
