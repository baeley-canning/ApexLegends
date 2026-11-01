@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run34.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0p34_matrix.ps1"
echo WRAPPER_END %date% %time% >> run34.log
