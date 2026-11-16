@echo off
pushd "%~dp0"
"..\tools\Godot_v4.4.1-stable_win64_console.exe" --path . --resolution 540x960 res://tests/formation_preview.tscn -- --painting --mixed --full
popd
