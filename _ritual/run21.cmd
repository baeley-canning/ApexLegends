@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run21.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p21.ps1"
echo WRAPPER_END %date% %time% >> run21.log
