# zzWeatherPlus 신규 앱 등록 체크리스트

## 0. 신규 앱으로 올라가는 이유
- `manifest.xml` 의 앱 ID가 새 값(`29cdcff5ad4e4107b5dfb4085364f809`)이라 스토어에서 **별도 앱**으로 등록된다.
  기존 zz날씨(`edccfce0-a425-4d11-9ccd-a6fed9563f7c`)는 그대로 남는다.
- 기존 앱을 업데이트하는 방식으로 바꾸려면 ID를 예전 값으로 되돌리면 된다(이 경우 530/830/1030/Explore2 사용자는 업데이트를 못 받음).
- 개발자 키: 이후 업데이트도 **같은 키**로 서명해야 하니 `developer_key` 백업.

## 1. 빌드
```powershell
pwsh tools/build-all.ps1     # 기기별 .prg (시뮬레이터/사이드로드 테스트용)
pwsh tools/export-iq.ps1     # 업로드용 bin/zzWeatherPlus.iq
```
- SDK 기기 목록에 `edge1060` 이 없으면 SDK Manager 에서 받거나 `manifest.xml` 에서 그 줄을 지운다.

## 2. 시뮬레이터 확인
- [ ] 기기마다(540/550/840/850/1040/1050/1060) `Simulation > Data Fields` 로 1·2·4·8분할, 전체화면
- [ ] **위치 없이 시작**: 위치 미설정 상태로 실행 → 크래시 없이 일출·일몰 표시 (저장값/서울 기본값)
- [ ] 위치 설정 후 재시작 → 그 위치 기준 시간으로 바뀌는지
- [ ] 날씨 데이터 없음(폰 연결 끊김) → 바람 `--`, 예보 `N/A` 아이콘, 크래시 없음
- [ ] 다크/라이트 배경
- [ ] 터치(840/850/1040/1050/1060): 1개 칸 4항목 순환, 2개 칸 오른쪽 3항목 순환
- [ ] 설정 변경(단위, 시간 형식, 칸 배치) 즉시 반영
- [ ] 실기기 사이드로드: `bin/zzWeatherPlus-<기기>.prg` → 기기 `GARMIN/APPS/`

## 3. 스토어 등록 (apps.garmin.com → 개발자 대시보드 → Upload an App)
| 항목 | 파일 / 내용 |
|---|---|
| 앱 패키지 | `bin/zzWeatherPlus.iq` |
| 앱 이름 | `description_ko.txt` / `description_en.txt` 의 [앱 이름] |
| 설명 | 각 파일의 [설명] 부분 |
| 새로운 기능 | [새로운 기능 / 버전 기록] |
| 버전 | 1.0.0 (`resources/settings/properties.xml` 의 appVersion 과 맞춤) |
| 앱 유형 | Data Field |
| 대표 이미지(아이콘) | `images/cover.png` (500x500, 둘레 10px 여백) |
| 히어로 이미지 | `images/hero_ko.png`, `images/hero_en.png` (1440x720, 언어별) |
| 화면 이미지 | `images/screen1~5_ko.png` / `_en.png` (500x500, 150KB 이하) |
| 기부 링크 | https://paypal.me/zzungga (설명 안에 포함) |

- 이미지는 `python store/make_assets.py` 로 다시 만들 수 있다 (레이아웃을 바꾸면 같이 재생성).

## 4. 등록 후
- 기존 zz날씨 설명 맨 위에 안내 추가 (예: "Edge 540/840/1040/1050/1060 사용자는 새 버전 zz날씨+를 받아주세요: <새 앱 링크>")
- 버전 올릴 때: `properties.xml` 의 appVersion, `description_*.txt` 의 버전 기록 같이 수정
