@echo off
cd /d "c:\Users\New User\OneDrive\Desktop\cheating\_ritual"
echo WRAPPER_START %DATE% %TIME% > run14.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "p14.ps1" >> run14.log 2>&1
echo WRAPPER_END exit=%ERRORLEVEL% %DATE% %TIME% >> run14.log
