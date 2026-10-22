@echo off
rem Open the project in the Godot editor
"%~dp0..\tools\Godot_v4.4.1-stable_win64.exe" --editor --path "%~dp0."
if errorlevel 1 pause
