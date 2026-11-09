@echo off
rem Solgukji - build the Android debug APK in one go (double-click or run from a terminal).
rem   1) release.py : sync version (changelog.json first entry) -> export_presets.cfg, update-notes html, build\version.txt
rem   2) Godot export : build\solgukji-<version>.apk
rem   3) copy : build\solgukji.apk  (latest copy, stored in git LFS)
rem One-time setup: tools\scripts\setup_android.ps1 (JDK / Android SDK / export templates / key).
rem New version: python tools\scripts\release.py --next "title"  then fill items in solgukji_godot\data\changelog.json
cd /d "%~dp0"
if not exist "build" mkdir "build"
python -I "tools\scripts\release.py"
if errorlevel 1 (
  echo [FAIL] release.py - check solgukji_godot\data\changelog.json
  pause
  exit /b 1
)
set /p VER=<"build\version.txt"
echo Version %VER% - exporting APK ...
"tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path "solgukji_godot" --export-debug "Android" "..\build\solgukji-%VER%.apk"
if errorlevel 1 (
  echo [FAIL] Godot export failed
  pause
  exit /b 1
)
copy /y "build\solgukji-%VER%.apk" "build\solgukji.apk" >nul
echo.
echo [OK] build\solgukji-%VER%.apk  (latest copy: build\solgukji.apk)
pause
