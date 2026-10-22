@echo off
rem Solgukji - launch the project with the bundled portable Godot
"%~dp0..\tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0."
if errorlevel 1 pause
