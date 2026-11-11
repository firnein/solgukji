@echo off
rem 솔국지 —— 집 PC 서버(server.bat, 포트 7777)를 Tailscale Funnel 고정 주소로 밖에 연다 (11/11, Cloudflare 임시 터널 tunnel.bat 대신).
rem 주소는 바뀌지 않는다: wss://<이 PC 이름>.<tailnet>.ts.net  (아래 status 에 나온다). --bg 라 한 번 켜면 재부팅 뒤에도 유지된다.
rem 끄기: "C:\Program Files\Tailscale\tailscale.exe" funnel --https=443 off
"C:\Program Files\Tailscale\tailscale.exe" funnel --bg 7777
"C:\Program Files\Tailscale\tailscale.exe" funnel status
pause
