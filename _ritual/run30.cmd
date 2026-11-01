@echo off
cd /d "%~dp0"
echo run30 %DATE% %TIME% > "%~dp0run30.log"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0p30_prep.ps1" >> "%~dp0run30.log" 2>&1
echo run30 wrapper exit=%ERRORLEVEL% %TIME% >> "%~dp0run30.log"
