@echo off
rem Solgukji - launch the project with the bundled portable Godot
rem Office PC (GZ-HSLEE9003): open the window at the bottom of the left vertical monitor (Godot coords 495,1500)
set POS=
if /i "%COMPUTERNAME%"=="GZ-HSLEE9003" set POS=--position 495,1500
"%~dp0..\tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0." %POS%
if errorlevel 1 pause
