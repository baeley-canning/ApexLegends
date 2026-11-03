@echo off
cd /d "%~dp0"
echo WRAPPER_START %date% %time% > run_h2.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0h2_gate.ps1"
echo WRAPPER_END %date% %time% >> run_h2.log
