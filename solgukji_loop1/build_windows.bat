@echo off
rem Solgukji - export the Windows game to ..\build\windows\솔국지.exe (one file, game data embedded)
chcp 65001 >nul
cd /d "%~dp0"
if not exist "..\build\windows" mkdir "..\build\windows"
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-release "Windows" "..\build\windows\솔국지.exe"
if errorlevel 1 pause
