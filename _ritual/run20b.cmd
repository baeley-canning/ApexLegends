@echo off
cd /d "c:\Users\New User\OneDrive\Desktop\cheating\_ritual"
echo WRAPPER_START %DATE% %TIME% > run20b.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "p20b.ps1" >> run20b.log 2>&1
echo WRAPPER_END exit=%ERRORLEVEL% %DATE% %TIME% >> run20b.log
