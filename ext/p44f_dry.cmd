@echo off
rem p44f smoke test: chunked windowed read, stops after 3 shape hits, 60 s cap.
cd /d "%~dp0"
set DUMP_OUT=p44f_dry.txt
set DUMP_PROG=p44f_dry_prog.txt
python basehunt.py --dry=3 --max-s=60
echo.
echo exit=%ERRORLEVEL%
echo --- _ritual\p44f_dry.txt
type "..\_ritual\p44f_dry.txt"
pause
