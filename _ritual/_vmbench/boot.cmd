@echo off
set d=C:\p37vm
mkdir %d% 2>nul
echo boot %DATE% %TIME% > %d%\boot.log
powershell -NoProfile -c "(New-Object Net.WebClient).DownloadFile('http://10.0.2.2:8080/stage2.ps1','%d%\stage2.ps1')" >> %d%\boot.log 2>&1
schtasks /create /tn p37st /tr "powershell -NoProfile -ExecutionPolicy Bypass -File %d%\stage2.ps1" /sc once /st 00:00 /ru SYSTEM /rl highest /f >> %d%\boot.log 2>&1
schtasks /run /tn p37st >> %d%\boot.log 2>&1
echo boot end %TIME% >> %d%\boot.log
