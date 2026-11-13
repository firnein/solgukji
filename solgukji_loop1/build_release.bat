@echo off
rem Solgukji - export the Android RELEASE apk to ..\build\solgukji-release.apk
rem Make the key once first: tools\scripts\make_release_key.ps1  (key lives in %USERPROFILE%\.solgukji, never in git)
rem The password is asked here and passed to Godot through environment variables only.
cd /d "%~dp0"
if not exist "%USERPROFILE%\.solgukji\release.keystore" (
  echo No release key. Run: powershell -ExecutionPolicy Bypass -File ..\tools\scripts\make_release_key.ps1
  pause
  exit /b 1
)
if not exist "..\build" mkdir "..\build"
set /p SOL_PW=Release key password:
set GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%USERPROFILE%\.solgukji\release.keystore
set GODOT_ANDROID_KEYSTORE_RELEASE_USER=solgukji
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=%SOL_PW%
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-release "Android" "..\build\solgukji-release.apk"
set SOL_PW=
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=
if errorlevel 1 pause
