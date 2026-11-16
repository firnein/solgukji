@echo off
rem Solgukji - get the current version's builds (APK + Windows exe) ready to share.
rem 11/16: the builds live in one folder, ..\build\release, and THAT folder is what Google Drive syncs / shares
rem (Drive for desktop > Preferences > add folder). Nothing is copied anywhere by default - this only zips the exe
rem next to it (솔국지-<version>.zip, the file friends download).
rem Optional copy: if ..\build\deploy_dir.txt exists (not in git), its first line is an extra folder to copy to,
rem e.g.  G:\내 드라이브\솔국지 . Delete / rename that file to stop copying.
chcp 65001 >nul
cd /d "%~dp0"
set /p VER=<"..\build\version.txt"
set N=0
if exist "..\build\release\solgukji-%VER%.apk" (
  echo   ready: ..\build\release\solgukji-%VER%.apk
  set /a N+=1
) else (
  echo   [skip] ..\build\release\solgukji-%VER%.apk not built
)
if exist "..\build\release\솔국지-%VER%.exe" (
  powershell -NoProfile -Command "Compress-Archive -Force -LiteralPath '..\build\release\솔국지-%VER%.exe' -DestinationPath '..\build\release\솔국지-%VER%.zip'"
  echo   ready: ..\build\release\솔국지-%VER%.zip
  set /a N+=1
) else (
  echo   [skip] ..\build\release\솔국지-%VER%.exe not built
)
if "%N%"=="0" (
  echo nothing built for version %VER%
  exit /b 1
)
if not exist "..\build\deploy_dir.txt" (
  echo done: version %VER% is in ..\build\release - the folder Google Drive syncs. No copy.
  exit /b 0
)
set /p DEST=<"..\build\deploy_dir.txt"
if not exist "%DEST%\" (
  echo copy destination not found: %DEST%
  echo - is Google Drive for desktop running and signed in?
  if not defined NOPAUSE pause
  exit /b 1
)
echo version %VER% -^> %DEST%
if exist "..\build\release\solgukji-%VER%.apk" copy /y "..\build\release\solgukji-%VER%.apk" "%DEST%\" >nul && echo   solgukji-%VER%.apk
if exist "..\build\release\솔국지-%VER%.zip" copy /y "..\build\release\솔국지-%VER%.zip" "%DEST%\" >nul && echo   솔국지-%VER%.zip
echo done: copied to %DEST%
