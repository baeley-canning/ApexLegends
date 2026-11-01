@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run24.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p24.ps1"
echo WRAPPER_END %date% %time% >> run24.log
