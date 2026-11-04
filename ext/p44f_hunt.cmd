@echo off
rem p44f bounded hunt: 240 s cap, duplicate to p44f_progress.txt for resume PA.
cd /d "%~dp0"
set DUMP_OUT=p44f_hunt.txt
set DUMP_PROG=p44f_progress.txt
python basehunt.py --max-s=240 %*
echo.
echo exit=%ERRORLEVEL%
echo --- _ritual\p44f_hunt.txt
type "..\_ritual\p44f_hunt.txt"
pause
