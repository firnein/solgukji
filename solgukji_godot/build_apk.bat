@echo off
rem 솔국지 —— 안드로이드 디버그 APK 를 ..\build\solgukji-<버전>.apk 와 ..\build\solgukji.apk (최신 복사본, 깃 LFS) 로 내보낸다.
rem 처음 한 번 tools\scripts\setup_android.ps1 (JDK · Android SDK · 내보내기 템플릿 · 키) 를 돌려 둔다.
rem 버전은 data\changelog.json 맨 앞 항목 (1.0a · 1.0b …). 새 버전: python ..\tools\scripts\release.py --next "제목" 뒤 items 를 채운다.
cd /d "%~dp0"
if not exist "..\build" mkdir "..\build"
python "..\tools\scripts\release.py"
if errorlevel 1 (
  echo release.py 실패 —— changelog.json 을 확인
  pause
  exit /b 1
)
set /p VER=<"..\build\version.txt"
echo 버전 %VER%
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-debug "Android" "..\build\solgukji-%VER%.apk"
if errorlevel 1 (
  pause
  exit /b 1
)
copy /y "..\build\solgukji-%VER%.apk" "..\build\solgukji.apk" >nul
echo 완료: ..\build\solgukji-%VER%.apk (최신 복사본 ..\build\solgukji.apk)
