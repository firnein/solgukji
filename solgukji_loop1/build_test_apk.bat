@echo off
rem Solgukji - export the battle test screen (scenes/main.tscn, practice battle tab) as a separate debug APK
rem -> ..\build\solgukji_test.apk  (package com.solgukji.test, installs next to the game)
cd /d "%~dp0"
if not exist "..\build" mkdir "..\build"
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-debug "Android 테스트" "..\build\solgukji_test.apk"
if errorlevel 1 pause
