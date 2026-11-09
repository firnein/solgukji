@echo off
rem 솔국지 —— 집 PC 서버(server.bat, 포트 7777)를 밖(사무실 · 데이터망)에서 닿게 하는 Cloudflare 임시 터널.
rem 창에 나오는 https://….trycloudflare.com 을 wss://… 로 바꿔 접속 시트 「직접 입력…」에 넣는다. 껐다 켜면 주소가 바뀐다.
rem cloudflared.exe 는 tools\cloudflared\ 에 둔다 (깃에 올리지 않음).
cd /d "%~dp0"
tools\cloudflared\cloudflared.exe tunnel --no-autoupdate --url http://localhost:7777
