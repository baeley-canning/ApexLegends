@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run25b.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p25b.ps1"
echo WRAPPER_END %date% %time% >> run25b.log
