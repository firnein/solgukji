# 솔국지

삼국지 랜덤 디펜스 HTML 프로토타입(`solgukji-9.html`)을 Godot 4.4 로 옮기는 프로젝트.
**이어서 작업할 때는 [`작업현황.md`](작업현황.md) 부터 읽는다.** 게임 구조·실행·점검 방법은 [`solgukji_godot/README.md`](solgukji_godot/README.md) 에 있다.

| 폴더 | 내용 |
|---|---|
| `solgukji_godot/` | Godot 프로젝트 (코드 · 데이터 · 그림 · 글꼴) |
| `tools/scripts/` | 데이터 추출 · 특기 생성 · 일러스트 시트 자르기 스크립트 |
| `prompts/` | 장수 일러스트 생성 프롬프트 |
| `solgukji-9.html` | 원본 HTML 프로토타입 |
| `references/` | 일러스트 레퍼런스 —— 촉 원본 시트, 예전에 받은 초상(동탁·주유·태사자·하후돈·하후연) |

## 새 PC 에서 시작하기
1. 이 저장소를 받는다.
2. **Godot 4.4.1 (Windows, 표준판)** 을 받아 `tools/` 에 압축을 푼다 —
   `tools/Godot_v4.4.1-stable_win64.exe`, `tools/Godot_v4.4.1-stable_win64_console.exe` 가 생기면 된다.
   (https://github.com/godotengine/godot/releases/tag/4.4.1-stable 의 `Godot_v4.4.1-stable_win64.exe.zip`)
3. 파이썬 3 과 `pip install pillow numpy` —— `tools/scripts/` 스크립트에 필요하다.
4. 처음 한 번 `tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot --import` (전역 클래스 등록).
5. `solgukji_godot/run.bat` 으로 실행, `edit.bat` 으로 에디터.
   3D 전투는 Forward+ 렌더러라 Vulkan 을 지원하는 그래픽 카드가 필요하다.
6. (온라인 대전) 서버로 쓸 PC 에서 `solgukji_godot/server.bat` —— 휴대폰은 「온라인 대전」에서 `ws://<그 PC 주소>:7777`.
7. (안드로이드 APK 를 만들 때만) `powershell -ExecutionPolicy Bypass -File tools\scripts\setup_android.ps1`
   —— JDK 17 · Android SDK · Godot 내보내기 템플릿 · 디버그 키를 `tools/` 아래에 포터블로 받는다(약 3GB).
   그다음 `solgukji_godot/build_apk.bat` → `build/solgukji.apk`.
