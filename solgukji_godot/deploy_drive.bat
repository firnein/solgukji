@echo off
rem Solgukji - copy the current version's builds (APK + Windows exe) to the Google Drive folder.
rem The destination folder is the first line of ..\build\deploy_dir.txt (not in git), e.g.  G:\내 드라이브\솔국지 배포
rem Needs Google Drive for desktop (the folder shows up as a normal folder under G:). Run build_apk.bat / build_windows.bat first.
chcp 65001 >nul
cd /d "%~dp0"
if not exist "..\build\deploy_dir.txt" (
  echo ..\build\deploy_dir.txt not found - write the Google Drive folder path on its first line
  if not defined NOPAUSE pause
  exit /b 1
)
set /p DEST=<"..\build\deploy_dir.txt"
if not exist "%DEST%\" (
  echo destination not found: %DEST%
  echo - is Google Drive for desktop running and signed in?
  if not defined NOPAUSE pause
  exit /b 1
)
set /p VER=<"..\build\version.txt"
echo version %VER% -^> %DEST%
set N=0
if exist "..\build\solgukji-%VER%.apk" (
  copy /y "..\build\solgukji-%VER%.apk" "%DEST%\" >nul && echo   solgukji-%VER%.apk && set /a N+=1
) else (
  echo   [skip] ..\build\solgukji-%VER%.apk not built
)
if exist "..\build\windows\솔국지-%VER%.exe" (
  rem the exe goes up zipped (솔국지-<version>.zip) - the bare exe is not uploaded
  powershell -NoProfile -Command "Compress-Archive -Force -LiteralPath '..\build\windows\솔국지-%VER%.exe' -DestinationPath '..\build\windows\솔국지-%VER%.zip'"
  copy /y "..\build\windows\솔국지-%VER%.zip" "%DEST%\" >nul && echo   솔국지-%VER%.zip && set /a N+=1
) else (
  echo   [skip] ..\build\windows\솔국지-%VER%.exe not built
)
echo done: %N% file(s) copied
if "%N%"=="0" exit /b 1
