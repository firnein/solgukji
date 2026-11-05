@echo off
chcp 65001 >nul
rem 윈도우 빌드 —— 솔국지.exe 를 만들고 친구에게 보낼 zip 으로 묶는다 (build\windows)
rem 1) 데이터 · 그림 가져오기  2) 내보내기(릴리스)  3) 압축  4) 폴더 열기
setlocal
for %%I in ("%~dp0..") do set ROOT=%%~fI
set GODOT=%~dp0Godot_v4.4.1-stable_win64_console.exe
set OUT=%ROOT%\build\windows

if not exist "%GODOT%" (
  echo [오류] Godot 실행 파일이 없습니다: %GODOT%
  pause
  exit /b 1
)
if not exist "%OUT%" mkdir "%OUT%"

echo [1/3] 데이터 · 그림 가져오는 중...
"%GODOT%" --headless --path "%ROOT%\solgukji_godot" --import >nul 2>&1

echo [2/3] 솔국지.exe 내보내는 중... (1~2분)
if exist "%OUT%\솔국지.exe" del "%OUT%\솔국지.exe"
"%GODOT%" --headless --path "%ROOT%\solgukji_godot" --export-release "Windows" "%OUT%\솔국지.exe" >nul 2>&1
if not exist "%OUT%\솔국지.exe" (
  echo [오류] 내보내기에 실패했습니다.
  pause
  exit /b 1
)

echo [3/3] 압축하는 중...
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\솔국지.exe' -DestinationPath '%OUT%\솔국지.zip' -Force"

echo.
echo 완료: %OUT%\솔국지.exe
echo       %OUT%\솔국지.zip  (친구에게 보낼 파일)
explorer "%OUT%"
endlocal
