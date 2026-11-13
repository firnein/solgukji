@echo off
rem 그림 시트 16~25 자르기 —— 시트16.png ~ 시트25.png 를 D:\Sol 에 두고 실행한다
rem (10장 전부 있어야 돌린다. 개별 시트는 자르기_이름.txt 의 명령을 직접 쓴다)
rem ※ 촉 초록 옷 있음 → --hole 없이 slice_panels.py

set ROOT=%~dp0..\..
set GODOT=%~dp0Godot_v4.4.1-stable_win64_console.exe
set OUT=%ROOT%\solgukji_godot\assets\portraits
set PY=python -I

cd /d %ROOT%

%PY% tools/scripts/slice_panels.py 시트16.png "주건평,동소,오의,왕평,마속" %OUT% 미리보기16.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트17.png "한당,장흠,감택,제갈근,보즐" %OUT% 미리보기17.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트18.png "기령,장임,허유,진림,장패" %OUT% 미리보기18.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트19.png "엄안,장포,맹달,반장,제갈각" %OUT% 미리보기19.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트20.png "우번,여범,고람,황조,장만성" %OUT% 미리보기20.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트21.png "관흥,오반,비의,공융,문빙" %OUT% 미리보기21.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트22.png "주연,왕쌍,조홍,한수,진무" %OUT% 미리보기22.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트23.png "하제,이각,황권,순유,도겸" %OUT% 미리보기23.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트24.png "길평,이의,이유,악진,요화" %OUT% 미리보기24.png || goto :fail
%PY% tools/scripts/slice_panels.py 시트25.png "능조,마충" %OUT% 미리보기25.png || goto :fail

"%GODOT%" --headless --path solgukji_godot --import
echo ── 잘랐다 · 임포트까지 끝 (미리보기1?.png 로 확인)
goto :eof

:fail
echo ── 시트를 다시 확인한다 (패널 수가 이름 수와 다름)
exit /b 1
