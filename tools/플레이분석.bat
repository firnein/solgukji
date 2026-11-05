@echo off
rem 플레이 기록 분석 —— build/플레이_분석.html 을 만들고 연다 (tools/scripts/analyze_playlog.py)
python "%~dp0scriptsnalyze_playlog.py"
start "" "%~dp0..uild\플레이_분석.html"
