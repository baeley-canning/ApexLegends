@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run33.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p33_flagflip.ps1" -PostBoot
echo WRAPPER_END %date% %time% >> run33.log
