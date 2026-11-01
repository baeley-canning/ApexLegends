@echo off
cd /d "c:\Users\New User\OneDrive\Desktop\cheating\_ritual"
echo WRAPPER_START %DATE% %TIME% > run4.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "p13_dirs4.ps1" >> run4.log 2>&1
echo WRAPPER_END exit=%ERRORLEVEL% %DATE% %TIME% >> run4.log
