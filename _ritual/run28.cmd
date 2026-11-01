@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run28.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p28_esp.ps1" %*
echo WRAPPER_END %date% %time% >> run28.log
