@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run25g.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p25g.ps1"
echo WRAPPER_END %date% %time% >> run25g.log
