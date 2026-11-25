# zzWeatherPlus (zz날씨+)

Garmin Edge **데이터 필드**. 라이딩 진행방향 기준 바람의 방향·속도, 12시간
일기예보, 일출/일몰 시간, 달 모양·밝기를 Titillium Web 비트맵 폰트로 크게 보여준다.
기존 **zzWeather (v1.1.6)** 를 다시 짠 버전.

## 대상 기기

| 버킷 | 기기 | 화면 | 배율 |
|---|---|---|---|
| A | Edge 540 / 550 / 840 / 850 | 246 x 322 | 1.0 |
| B | Edge 1040 | 282 x 470 | 1.15 |
| C | Edge 1050 / 1060 | 480 x 800 | 1.95 |

`minApiLevel` = **4.1.0**. 530/830/1030/1030plus/Explore2 는 대상에서 뺐다.
`edge1060` 이 설치된 SDK 의 기기 목록에 없으면 SDK Manager 에서 기기를 받거나,
`manifest.xml` 에서 그 줄을 지우고 빌드한다.

## zzWeather 대비 바뀐 점

### 크래시 수정
| 원인 (기존) | 수정 |
|---|---|
| 1030 등에서 `Weather.getSunrise/getSunset` 미지원 → 심볼 없음 | `has` 검사 후 호출, 없거나 null 이면 **자체 계산**(NOAA 일출 방정식, ±1~2분)으로 대체 (`Astro.mc`) |
| 위치를 못 읽으면 sunrise/sunset 이 null → `Gregorian.info(null)` 크래시 | 위치가 null 이 되는 경로 자체를 없앰 (아래 `LocationStore`) |
| "설정을 한 번 저장하면 해결" — 설정 동기화로 `LastLocationLat/Lng` 가 다시 채워져서 | **앱이 켜지는 순간(`App.onStart`) 위치를 읽어 즉시 저장**. 이후 1분마다 확인, 1km 이동 또는 30분 경과 시 저장, 타이머 정지/리셋·앱 종료 시 저장 |
| `cc.windBearing.toFloat()`, `hf.windBearing + 180`, `hf.temperature * 1.8` 가 null 일 때 | 모든 Weather 필드 null 체크 + try/catch (`WeatherData.mc`) |
| 음력표 경계에서 `lunarDay = 0` → `moon_intensity_set[-1]`, 30일 → `substring` 범위 초과 | 음력표 제거. 태양·달 황경으로 실제 위상·조명률 계산 |
| `Properties.getValue` 결과를 그대로 사용 | `Config.mc` 에서 try/catch + 기본값 + 범위 검사 |
| 정오(12시대) 일출/일몰이 `12:xxa` 로 표시 | 12시간제 a/p 판정 수정 |

### 위치 읽기 순서 (`LocationStore.mc`)
1. 활동 중 실시간 GPS (`Activity.Info.currentLocation`)
2. `Position.getInfo()` 의 현재/마지막 위치 (`QUALITY_LAST_KNOWN` 이상)
3. 폰에서 받은 날씨 관측 위치 (`observationLocationPosition`) — 실내에서 켜도 대략 위치 확보
4. `Application.Storage` 저장값 — 저장은 여기에만 (기기 밖으로 안 나가고, 설정 동기화로 덮어써지지 않음)
5. `Properties` 의 `LastLocationLat/Lng` 기본값 (읽기만 함)
6. 기본값 (서울)

### 화면
- 레이아웃 XML 대신 코드로 그림(zzCadence 방식). 칸 크기에 따라 폰트를 골라 꽉 채움.
- 바람: 링 색 = 맞바람 빨강 / 옆바람 회색 / 뒷바람 파랑, **링의 구멍 = 바람이 들어오는 쪽**.
  가운데 화살표는 `wind.svg`(location-arrow) 모양을 벡터로 회전시켜 그림.
- 예보: 12시간을 2초마다 넘기며 아이콘(낮/밤 구분은 실제 일출·일몰 기준) + 시각 +
  바람 방향 화살표 + **강수확률%** (새로 추가).
- 일출/일몰: 이미 지난 시각은 흐리게.
- 달: 아이콘 폰트 대신 실제 위상으로 그림(남반구는 좌우 반전) + 밝기% + **월령(d)**.
- 설정 추가: **칸 배치**(자동 / 항상 하나만 크게), **시간 표시**(기기 설정 / 12h / 24h).

## 칸 배치 (자동)

| 칸 | 표시 |
|---|---|
| 반폭 (540 122px, 1040 140px, 1050 239px) | 선택 항목 1개 |
| 전폭 + 낮음 (540 h<120, 1040 h<138, 1050 h<234) | 좌: 바람 / 우: 선택 항목 (선택이 바람이면 일출·일몰) |
| 전폭 + 높음 | 2x2: 바람 · 예보 / 일출일몰 · 달 |

터치 기기(840/850/1040/1050/1060): 칸을 탭하면 표시 항목 전환 (설정에서 끌 수 있음).
- 1개 칸: 바람 → 예보 → 일출일몰 → 달
- 2개 칸: 왼쪽은 바람 고정, 오른쪽만 예보 → 일출일몰 → 달 (바람은 건너뜀)
- 2x2 칸: 4개가 다 보이므로 변화 없음
- 탭으로 바꾼 항목은 설정 저장 또는 활동 저장/리셋 시 설정값으로 돌아감

`tools/preview.png` 에 실제 폰트로 렌더한 미리보기가 있다 (`python tools/preview.py`).

## 설정 (Connect IQ 앱 / Garmin Express)

| 설정 | 키 | 기본값 |
|---|---|---|
| 표시 항목 | `dataType` | 바람 |
| 칸 배치 | `layoutMode` | 자동 |
| 진행방향을 위로 | `northOrientation` | 켬 |
| GPS 이동 방향 사용 (끄면 나침반) | `showGpsOrientation` | 켬 |
| 풍속 단위 | `windSpeedUnit` | m/s |
| 시간 표시 | `timeFormat` | 기기 설정 |
| 탭하면 항목 전환 | `touchScreen` | 켬 |

## 폰트

CIQ 는 TTF 임베드가 안 되므로 필요한 글리프만 담은 BMFont(.fnt + png) 를 쓴다.
`tools/FntGen.java` 로 생성 (JDK 11+, 추가 라이브러리 없음):

```powershell
# 숫자/단위 - Titillium Web Bold (zzCadence 와 같은 TTF)
java tools/FntGen.java tools/ttf/TitilliumWeb-Bold.ttf resources/fonts tw " %-./0123456789:adfhkmpst" - 16 20 24 30 38 48 60 76 96 120

# 날씨 아이콘 - Weather Icons 2.1.0, PUA 코드포인트를 A~Z 로 리매핑
java tools/FntGen.java tools/ttf/weathericons-regular-webfont.ttf resources/fonts wx "ABCEFHRSZabcefhrsGg" "A=F00D,a=F02E,B=F000,b=F022,C=F002,c=F086,E=F00A,e=F02A,F=F003,f=F04A,H=F006,h=F026,R=F008,r=F028,S=F010,s=F02D,Z=F07B,G=F051,g=F052" 20 26 32 40 52 64 80 100
```

| 문자 | 아이콘 (대문자 낮 / 소문자 밤) |
|---|---|
| A a | 맑음 |
| C c | 구름 |
| F f | 안개·박무·먼지 |
| H h | 진눈깨비·우박 |
| E e | 눈 |
| S s | 뇌우·폭풍 |
| B b | 바람·돌풍 |
| R r | 비 |
| Z | 모름 |
| G g | 일출 / 일몰 |

생성기가 출력하는 `px adv cap` 값을 `source/Layout.mc` 의 `TW_*`/`WX_*` 표와
`tools/preview.py` 에 맞춘다. 크기를 바꾸면 `resources/fonts/fonts.xml` 과
`zzWeatherPlusView.mc` 의 `twRez/wxRez` 도 같이.

라이선스: Titillium Web — SIL OFL 1.1 (`tools/ttf/OFL.txt`).
Weather Icons (Erik Flowers) — 폰트 SIL OFL 1.1, 코드 MIT.
진행방향 화살표 모양 — Font Awesome Free `location-arrow` (CC BY 4.0).

## 빌드

```bash
SDK=~/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-8.4.1-2026-02-03-e9f77eeaa
"$SDK/bin/monkeyc" -f monkey.jungle -d edge840 -o bin/zzWeatherPlus-edge840.prg -y ~/.Garmin/ConnectIQ/developer_key -w
```

전체 기기: `pwsh tools/build-all.ps1`

시뮬레이터: `Simulation > Data Fields` 로 칸 크기, `Simulation > Set Position` 으로 위치,
날씨는 `Simulation > Weather` 에서 주입.

## 구조

```
source/
  zzWeatherPlusApp.mc       진입점. onStart 에서 위치 즉시 저장
  zzWeatherPlusView.mc      DataField - compute/onUpdate, 패널 4종 그리기
  zzWeatherPlusDelegate.mc  탭 -> 표시 항목 순환
  Config.mc                 설정 스냅샷 (안전 읽기)
  LocationStore.mc          위치 읽기/저장
  WeatherData.mc            Weather API 래퍼 (null 안전) + 날씨 코드 -> 아이콘
  Astro.mc                  일출/일몰 (API + 자체 계산), 달 위상
  Layout.mc                 폰트 표, 칸 분류, 폰트 맞추기
resources/          fonts/ strings/ settings/ drawables/
resources-kor/      한국어 문자열
resources-edge*/    기기별 런처 아이콘
tools/
  FntGen.java       TTF -> BMFont (.fnt/.png), 코드포인트 리매핑 지원
  preview.py        레이아웃 미리보기 PNG
  build-all.ps1     전체 기기 빌드
  ttf/              원본 폰트
```
