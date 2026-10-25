@echo off
rem Solgukji - export the Android debug APK to ..\build\solgukji.apk
rem Run tools\scripts\setup_android.ps1 once first (JDK, Android SDK, export templates, keystore).
cd /d "%~dp0"
if not exist "..\build" mkdir "..\build"
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-debug "Android" "..\build\solgukji.apk"
if errorlevel 1 pause
