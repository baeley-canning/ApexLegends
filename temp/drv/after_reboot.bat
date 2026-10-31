@echo off
rem Step 2 of 2 (after the reboot with test signing on):
rem   start apexr, wait for the game, prove a driver read of its image.
rem Self-elevates. Optional arg:  scan  -> also run the full string scan.
setlocal enabledelayedexpansion
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%1' -Verb RunAs"
  exit /b
)

set T=C:\Users\New User\OneDrive\Desktop\cheating\temp
set LOG=%T%\drv\after_reboot.txt
> "%LOG%" echo === boot/signing state
>> "%LOG%" bcdedit /enum {current} 2>&1 | findstr /i "testsigning"
>> "%LOG%" powershell -NoProfile -Command "try{'SecureBoot=' + (Confirm-SecureBootUEFI)}catch{'SecureBoot=unknown'}" 2>&1
>> "%LOG%" echo === start driver
>> "%LOG%" sc start apexr 2>&1
>> "%LOG%" sc query apexr 2>&1

set /a n=0
:waitgame
tasklist /fi "imagename eq r5apex_dx12.exe" 2>&1 | findstr /i "r5apex_dx12" >nul
if not errorlevel 1 goto gotgame
set /a n+=1
if !n! geq 90 goto gotgame
echo waiting for r5apex_dx12.exe ... (!n!/90)
timeout /t 10 /nobreak >nul
goto waitgame
:gotgame
>> "%LOG%" echo === game
>> "%LOG%" tasklist /fi "imagename eq r5apex_dx12.exe" 2>&1

>> "%LOG%" echo === selftest
call "%T%\run_kx.bat" --selftest
>> "%LOG%" type "%T%\kx_console.txt"

if /i "%~1"=="scan" (
  >> "%LOG%" echo === full scan
  call "%T%\run_kx.bat"
  >> "%LOG%" type "%T%\kx_console.txt"
)
>> "%LOG%" echo === done
type "%LOG%"
pause
