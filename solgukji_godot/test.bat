@echo off
rem Solgukji - old test screen (card list / practice battle), scenes/main.tscn
"%~dp0..\tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0." res://scenes/main.tscn -- --tab=1
if errorlevel 1 pause
