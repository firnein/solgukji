@echo off
rem Solgukji - export the Windows game to ..uild\windows\솔국지.exe (one file, data embedded)
chcp 65001 >nul
cd /d "%~dp0"
if not exist "..uild\windows" mkdir "..uild\windows"
"..	ools\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-release "Windows" "..uild\windows\솔국지.exe"
if errorlevel 1 pause
