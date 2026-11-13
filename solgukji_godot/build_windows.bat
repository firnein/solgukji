@echo off
rem Solgukji - export the Windows game to ..\build\windows\솔국지-<version>.exe (one file, game data embedded)
rem and copy it to ..\build\windows\솔국지.exe (latest). Version = first entry of data\changelog.json (same as build_apk.bat).
chcp 65001 >nul
cd /d "%~dp0"
if not exist "..\build\windows" mkdir "..\build\windows"
python "..\tools\scripts\release.py"
if errorlevel 1 (
  echo release.py failed - check data\changelog.json
  pause
  exit /b 1
)
set /p VER=<"..\build\version.txt"
echo version %VER%
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-release "Windows" "..\build\windows\솔국지-%VER%.exe"
if errorlevel 1 (
  pause
  exit /b 1
)
copy /y "..\build\windows\솔국지-%VER%.exe" "..\build\windows\솔국지.exe" >nul
echo done: ..\build\windows\솔국지-%VER%.exe (latest copy ..\build\windows\솔국지.exe)
