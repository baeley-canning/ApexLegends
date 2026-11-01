@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run29.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p29_gate2.ps1" %*
echo WRAPPER_END %date% %time% >> run29.log
