@echo off
rem Solgukji - multiplayer server (headless). Phones connect to ws://<this PC address>:7777
rem Change the port with: server.bat 8000
cd /d "%~dp0"
set PORT=%1
if "%PORT%"=="" set PORT=7777
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . res://scenes/server.tscn -- --port=%PORT%
pause
