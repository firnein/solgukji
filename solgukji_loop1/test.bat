@echo off
rem Solgukji - old test screen (card list / practice battle), scenes/main.tscn
set POS=
if /i "%COMPUTERNAME%"=="GZ-HSLEE9003" set POS=--position 495,1500
"%~dp0..\tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0." res://scenes/main.tscn %POS% -- --tab=1
if errorlevel 1 pause
