# 솔국지 — Godot 이식판 (PC · 안드로이드)

`../solgukji-9.html` (모바일 HTML 프로토타입)을 Godot 4.4로 옮겼다.
**게임 화면**(징집·조합·편성·전투·계보·순위 · 7일 21페이즈 · 토너먼트 · 저장)과 **실시간 3D 전장**이 있다.
가로 화면 고정. PC 는 Forward+ (그림자·SSAO·볼류메트릭 안개), 휴대폰은 Mobile 렌더러로 돈다.
예전 점검 화면(카드 도감·연습 전투)은 `--tab=…` 인자로 연다 (`scenes/main.tscn`).

전장은 토탈워처럼 보이지만 판정은 원본 턴제 엔진 그대로다. `battle_view.gd` 가 엔진의 행동들을
시간축에 겹쳐 깔고(`STEP` 초 간격), 근접 부대는 상대에 닿을 때 피해가 들어간다.
각 부대는 엔진이 정한 공격 순서를 미리 내다보고(`War3D.direct`) 시작부터 상대에게 달려가 붙으며,
궁병·지략 계열은 제 차례 사이에도 계속 쏘고 던진다(피해는 엔진 이벤트 때만).
피해는 이벤트 순간에 한꺼번에 깎지 않고, 그 부대가 다음에 피해를 받을 때까지(0.8~3.5초) 흘려 넣는다.
전투가 끝나면 화면 병력이 엔진 최종값과 같은지 확인하고 다르면 경고를 띄운다. 병력은 이벤트별
증감으로 적용해 연출 순서가 섞여도 최종 결과는 엔진과 같다.

## 전투 길이
대전·토너먼트는 50~60초가 되게 행동 간격을 벌린다(`BattleView.PVP_LEN = 52` · `pace` 최대 7배 · 피해 흘려 넣는 창도 같은 배율). 판정은 그대로라 결과는 같다.
토벌은 2배속(`QUEST_SPEED`)으로 시작한다. 한쪽이 금세 무너지는 판은 7배로도 40초 안팎에서 끝난다.

## 실행
- `run.bat` — 게임 실행
- `edit.bat` — Godot 에디터로 열기
- `build_apk.bat` — 안드로이드 디버그 APK → `../build/solgukji.apk` (아래 「안드로이드」)
- Godot 은 `../tools/` 에 포터블로 들어 있다 (설치 불필요).

## 구조
| 파일 | 내용 |
|---|---|
| `data/game.json` | HTML의 데이터 상수 전부 (카드 208 · 조합 200 · 아이템 95 · 진형 8 …) |
| `scripts/db.gd` | 데이터 로더(autoload `DB`) · 보드 생성 · 자동 편성 · 스킬 설명 |
| `scripts/battle.gd` | 전투 엔진 — 원본 `runBattle()` 이식. 이벤트에 연출용 필드(fx/a/f/n/m)를 더했다 |
| `scripts/art.gd` | 초상 그리기 — 실제 그림이 없으면 수묵 실루엣 플레이스홀더 |
| `scripts/card_view.gd` | 카드 한 장 (등급 테두리 · 세력 배지 · 병종 아이콘 · 신화 금박) |
| `scripts/field/squad.gd` | 부대 하나 — 병사 인형 배치·이동·전사·대열 재정렬·패주 |
| `scripts/war3d/war3d.gd` | 3D 전장 — 지형·하늘·빛·안개·숲, 병사 GPU 인스턴싱, 화살·불길·물보라, 토탈워식 카메라 |
| `scripts/war3d/models.gd` | 병종별 로우폴리 병사·말·무기·나무·바위·산 (코드로 생성) |
| `scripts/war3d/mesh_kit.gd` | 로우폴리 모델을 상자·원기둥·구로 쌓는 도구 |
| `shaders/*.gdshader` | 병사 세력색·시신·피격, 지형 결, 깃발 펄럭임 |
| `scripts/battle_view.gd` | 실시간 재생 감독 — 시간축 배치, 카메라(휠·끌기), 머리표, 아래 부대 카드, 로그 |
| `tests/selftest.tscn` | 엔진 자가 점검 (헤드리스) |
| `scripts/game/run.gd` | 한 판의 진행 상태 — 원본 `S` · 징집·조합·환전·편성·7일 진행·토벌·대전·토너먼트 · 저장(`user://save.json`) |
| `scripts/game/settings.gd` | 설정 — 품질(병사 수·AA·그림자·SSAO) · 자동 전투 (`user://settings.cfg`) |
| `scripts/ui/game_screen.gd` | 게임 화면 — 머리띠 · 왼쪽 탭 · 페이지 · 오른쪽 시트 · 알림 · 전투 전환 · 제목 화면 (`scenes/game.tscn`, 시작 장면) |
| `scripts/ui/deploy_page.gd` | 편성 — 진형 · 9칸 편성판(끌어 놓기·칸끼리 바꾸기) · 손패 · 시너지 · 보급품 |
| `scripts/ui/card_tile.gd` | 작은 카드 — 탭 · 길게 눌러 끌기 |
| `scripts/ui/ui.gd` | 화면 부품 · 테마 (손가락 기준 버튼 높이 48+) |
| `tests/game.tscn` | 진행 점검 — 단순 규칙으로 한 판을 끝까지 돌며 페이즈마다 저장·불러오기 |

데이터를 HTML에서 다시 뽑으려면:
`python -I ../tools/scripts/extract.py ../solgukji-9.html data/game.json`

## 게임 화면
원본 HTML 의 화면을 가로 화면에 옮겼다. 왼쪽 탭: 징집 · 조합 · 편성 · 전투 · 계보 · 순위. 카드를 누르면 오른쪽 시트에 상세(능력치·스킬·고유기·특기·선호 구역·만드는 법·한 단계 위 조합)가 열린다.
- 진행 규칙·수치는 원본 그대로 (`DB.D` 의 DRAWS·PICKS·QPV·QUEST_REWARD… · `Run` 상단 상수).
- **원본과 다른 점**: 전투 결과는 전투가 *끝날 때* 반영한다(고유기·군령 입력으로 결과가 바뀌므로). 시작할 때 전투 재료(시드·양쪽 덱)를 `Run.battle` 에 적고, 입력할 때마다 저장한다. 전투 도중 앱이 꺼지면 다음에 열 때 적어 둔 입력으로 다시 계산해 마무리한다(남은 부분은 자동).
- 상대 AI: 대전·토너먼트 상대는 `smart`(비동기 상대), 토벌의 적은 `auto`.
- 저장: 행동할 때마다 `user://save.json`. 키 순서를 지키고 실수를 다 살려 쓴다 —— 그래야 불러온 판이 같은 결과로 이어진다(`tests/game.tscn` 이 확인).
- 편성: 손패 카드를 **길게 눌러** 칸으로 끈다 / 카드를 눌러 고른 뒤 칸을 누른다 / 칸을 눌러 목록에서 고른다. 칸끼리 끌면 자리를 바꾸고, 칸을 손패 쪽으로 끌면 내린다.
- 휴대폰 뒤로 가기: 시트를 닫고, 그다음엔 제목 화면. 앱이 가려지면 저장한다.

점검용 인자 (`--` 뒤): `--gnew=시드 --gplay=페이즈수`(자동으로 진행해 둔 판) `--gpage=draw|forge|deploy|war|line|rank`
`--gsheet=card:c39|slot:3|menu|settings` `--gbattle=quest|pvp|tour [--speed=2 --gclose]` `--gq=0~2`(품질) `--gshot=경로.png --after=초`.
예) `Godot.exe --path . --rendering-method mobile -- --gq=0 --gnew=7 --gplay=6 --gbattle=quest --gshot=out.png --after=10` (휴대폰 렌더러로 미리 보기)

## 온라인 대전 (집 PC 서버)
- **서버**: `server.bat` (포트 7777, `server.bat 8000` 처럼 바꿀 수 있다) —— 화면 없는 Godot 가 `scenes/server.tscn` 을 띄운다. 첫 줄에 이 PC 주소 후보를 찍는다.
- **휴대폰**: 제목 화면 「온라인 대전」 → 서버 주소(`ws://192.168.x.x:7777`)·이름 → 방 만들기(빠른·보통) 또는 코드로 참가 → 대기실에서 방장이 시작(빈자리는 봇, 모두 8자리).
- **진행**: 페이즈마다 준비(빠른 100초 · 보통 160초) → 서버가 토벌(각자)·대전(사람끼리 짝, 남으면 봇)을 계산 → 관전 100초 (토벌은 2배속 10~20초, 대전은 50~60초). 하루 빠른 약 10분 · 보통 약 13분. 모두 '준비 완료'면 바로 넘어간다. 7일째 저녁은 8인 토너먼트.
- **판정은 서버**: 휴대폰은 명령(`Run.COMMANDS`)만 보내고 서버가 같은 명령을 그 사람의 `Run` 에 적용해 상태를 돌려준다. 전투 결과는 서버가 계산해 통째로 보낸다(32KB 넘으면 gzip, 보통 15~30KB) —— 기기마다 실수 계산이 미세하게 달라도 결과가 갈라지지 않는다.
- 사람끼리 대전은 한 번만 계산하고 B 쪽 사람에게는 `Run.flip_res` 로 진영을 뒤집어 준다 (늘 내 쪽이 A·왼쪽).
- **1단계 —— 전투는 양쪽 자동**(고유기·군령을 AI 가). 전투 화면은 재생만 한다(`BattleView.play_res`, 입력 잠금).
- 끊기면: 그동안은 준비 시간 끝에 AI 가 대신 징집·조합·편성. 휴대폰은 3초마다 다시 붙고, 같은 토큰(`user://net.cfg`)이라 자리로 돌아간다. 메뉴의 「방에서 나가기」는 자리를 AI 에게 넘긴다.
- **밖에서 접속**: 공유기에서 TCP 7777 을 이 PC 로 포트포워딩(+ 공유기 DDNS). 통신사가 공인 IP 를 안 주면(CGNAT) Cloudflare Tunnel 로 `wss://…` 주소를 만든다. Windows 방화벽에서 Godot 를 허용해야 한다(처음 띄울 때 묻는 창에서 허용).
- 점검: `res://tests/net.tscn -- --players=4` —— 서버 + 가짜 플레이어 N명이 실제 WebSocket 으로 한 판(점검 모드는 멸망 없음 → 토너먼트까지), 2일차에 한 명 끊었다 재접속, 대전 승패·제목 확인.
  창으로 보기: `server.bat` 뒤 `Godot.exe --path . -- --gonline=ws://127.0.0.1:7777 --gname=유비 --gcreate=fast --gstart=2 --gauto` 와 `… --gname=조조 --gjoin=유비 --gauto`.
- 파일: `scripts/net/server.gd`(접속·방 목록·메시지) · `scripts/net/room.gd`(방 진행·짝짓기·AI 대행·토너먼트) · `scripts/net/client.gd`(WebSocket) · `scripts/ui/online.gd`(접속 시트·대기실·온라인 전투 탭·재생).

## 안드로이드
1. 처음 한 번 `powershell -ExecutionPolicy Bypass -File ..\tools\scripts\setup_android.ps1` —— JDK 17 · Android SDK(build-tools 34 · android-34) · Godot 내보내기 템플릿 · 디버그 키를 `../tools/` 아래에 포터블로 받는다 (약 3GB, 시스템 설치 없음). `tools/_sc_` 때문에 Godot 설정·템플릿은 `tools/editor_data/` 에 있다.
2. `build_apk.bat` → `../build/solgukji.apk` (arm64, 디버그 서명). 휴대폰에서 USB 디버깅을 켜고 `..\tools\android\sdk\platform-tools\adb install -r ..\build\solgukji.apk`, 또는 파일을 옮겨 설치.
- 렌더러는 Mobile (SSAO·볼류메트릭 안개 없음). 품질 낮음 = 병사 40% · MSAA 끔 · 그림자 2분할. 휴대폰은 처음에 '낮음'.
- 글꼴은 동봉한 나눔고딕·나눔명조(OFL). 초상은 내보낸 앱에선 임포트된 텍스처로 읽는다.
- 내보내기 설정: `export_presets.cfg` (패키지 `com.solgukji.game`, `data/*.json` 포함, `tests/` 제외).

## 고유기 (불멸·신화)
`data/ultimates.json` —— 인물 34명의 전용 기술. 이름·외침·연출 계열(vfx)·효과(eff)를 적는다.
수치는 신화 기준이고 불멸 카드는 80%. 신화는 2~3턴, 불멸은 3~4턴에 처음 쓸 수 있고 쿨타임 3턴이다.
발동하면 슬로모션 + 화면 가운데 초상 컷인(기술명·외침) + 카메라 접근 뒤 대형 이펙트(`scripts/war3d/ult_fx.gd`)와 함께 피해가 들어간다.
컷인은 한 번에 하나씩 나온다.

## 특기 (개인·단체 패시브)와 치명타
`data/passives.json` —— `python -I ../tools/scripts/gen_passives.py data/game.json data/passives.json` 로 만든다.
특기 목록(투쟁·신속·용장·맹장·비장·철벽·불굴… / 인덕·위풍·군주·철기·창진·연사·고무·결속·선봉·후원…)과 인물 85명 배정은 그 스크립트에 있다.
개인 특기는 고급부터, 단체 특기는 희귀부터. 단체 특기 대상: 아군 전원 · 진형 열 · 병종 · 같은 세력 · 적 전원.
같은 이름의 단체 특기는 둘까지 겹친다(두 번째는 절반). 원본의 패시브 13종(불굴·군주 등)은 이 체계로 옮겼다.
치명타: 기본 5% · 1.5배 (용장·맹장·궁신·연사·명성 등이 올린다). 책략 치명타는 귀모 같은 특기가 있어야 난다.
덱빌딩 점검: `godot --headless --path . res://tests/deck.tscn -- --games=150` (시너지 덱 vs 무작위 덱 승률)

## 전투 중 개입 (고유기 직접 발동 · 군령)
기획과 측정은 [`../docs/전투개입_기획.md`](../docs/전투개입_기획.md). 입력은 [행동 번호, 진영, 종류, 값] 이고 같은 시드 + 같은 입력이면 같은 결과다.
화면은 탭마다 처음부터 다시 계산해 뒤 시간표만 바꾼다. 점검: `res://tests/control.tscn`(조작 효과), `res://tests/determinism.tscn`(결정성).
`control.tscn` 인자: `--mixed=1`(섞인 등급 덱) · `--tactics=1 --pv=1000`(전술 9종) · `--p1=tac:즉시:공세 --p2=smart`(맞대결). 비교용: `--links=0`(특기–군령 연결 끔) · `--amp=1.3`(배수진 배율) · `--breach=0.25`(돌격의 방진 무시, 기본 0).
정책: `auto` · `smart` · `manual` · `tac:<즉시|영리|위기>:<공세|영리|수비>`(덱 주인이 정하는 비동기 AI). 특기–군령 연결은 `data/passives.json` catalog 의 `cmd`.
실행 인자: `--auto`(자동 전투), `--tap=8:돌격,22:ult`(그 시각에 군령·고유기를 누른 것처럼).

## 밸런스 점검
`godot --headless --path . res://tests/balance.tscn -- --trials=120 --tiers=7,8 --ult=1`
같은 등급 8장 + 대상 1장으로 같은 상황 N판을 돌려 카드별 기여 승률, 병종·세력 평균, 등급 격차를 낸다.
결과 표는 `tests/out_balance.csv`. `--ult=0` 으로 고유기를 끄고 비교할 수 있다.

## 그림 넣기
파일을 떨궈 넣기만 하면 플레이스홀더가 바뀐다 (임포트 불필요).

- 장수: `assets/portraits/<인물 이름>.png` — 예) `관우.png`
  인물 이름은 카드 이름의 마지막 단어다. "미염공 관우", "의절 관우", "관우"가 모두 `관우.png` 한 장을 나눠 쓴다. → 85장이면 장수 전부
- 병사(기본·일반 등급): `assets/troops/<병종>.png` — 예) `창병.png` (8장)
- 세로로 긴 그림(약 3:4)을 권장한다. 위쪽 기준으로 잘라 채운다.

## 점검용 실행 인자
```
Godot.exe --path . -- --tab=1 --level=2 --shot=out.png --after=3
```
`--tab` 0 도감 / 1 전투, `--level` 0~3, `--pick` 카드 id, `--filter` 등급, `--speed` 배속,
`--shot` 지정 시간 후 화면을 PNG로 저장하고 종료.
`--frames=N --every=초` 연속 장면 저장, `--near=거리 --nx=X --yaw=각` 가까운 시점,
`--probe=N` 0.5초마다 fps와 부대-병사 간격을 출력하고 종료.
`--seed=N` 같은 전투 다시 만들기, `--nosmooth` 예전처럼 한꺼번에 깎기,
`--lumps=초` 병사가 얼마나 몰려서 쓰러지는지 측정 (예: `--seed=12 --lumps=90` 과 `--seed=12 --nosmooth --lumps=90` 비교).

## 글꼴
`assets/fonts/NanumMyeongjo-ExtraBold.ttf` (제목) · `NanumGothic-Regular/Bold.ttf` (본문) — SIL Open Font License (`OFL.txt`, `OFL-NanumGothic.txt`). 나눔에 없는 글자만 시스템 글꼴로 넘긴다.
