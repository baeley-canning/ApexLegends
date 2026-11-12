@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run_va12.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0h320_va.ps1" --out=_ritual\h320_va12.txt --secs=120 >> run_va12.log 2>&1
echo WRAPPER_END %date% %time% rc=%ERRORLEVEL% >> run_va12.log
