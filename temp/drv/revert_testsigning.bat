@echo off
rem ===========================================================================
rem  revert_testsigning.bat -- EAC/Javelin refuses to start while Windows is in
rem  test-signing mode ("unacceptable configuration").  This puts the machine
rem  back to a stock boot config and removes the two test-signed leftovers
rem  (apexr / apexdrv services + files) so nothing unsigned is even on disk.
rem
rem  Nothing is lost: the .sys files are copied to .\backup\ first.
rem  Arg "reboot" also restarts the box (test signing is only re-read at boot).
rem ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem --- self-elevate (one UAC prompt) -----------------------------------------
set ARG=%~1
if not defined ARG set ARG=none
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ARG%' -Verb RunAs"
  exit /b
)

set LOG=%~dp0revert.txt
> "%LOG%" echo === revert started %DATE% %TIME%

echo. >> "%LOG%"
echo === before >> "%LOG%"
bcdedit /enum {current} >> "%LOG%" 2>&1

if not exist backup md backup
for %%F in (apexr.sys apexdrv.sys) do (
  if exist "%SystemRoot%\System32\drivers\%%F" copy /y "%SystemRoot%\System32\drivers\%%F" "backup\%%F" >nul 2>&1
)

echo. >> "%LOG%"
echo === stop/delete services >> "%LOG%"
for %%S in (apexr apexdrv) do (
  sc.exe stop %%S >> "%LOG%" 2>&1
  sc.exe delete %%S >> "%LOG%" 2>&1
)

echo. >> "%LOG%"
echo === remove driver files >> "%LOG%"
for %%F in (apexr.sys apexdrv.sys) do (
  if exist "%SystemRoot%\System32\drivers\%%F" (
    del /f /q "%SystemRoot%\System32\drivers\%%F" >> "%LOG%" 2>&1 && (
      if exist "%SystemRoot%\System32\drivers\%%F" (echo   %%F STILL PRESENT) else (echo   %%F deleted)
    ) >> "%LOG%"
  ) else (
    echo   %%F already gone >> "%LOG%"
  )
)

echo. >> "%LOG%"
echo === clear test signing >> "%LOG%"
bcdedit /deletevalue testsigning >> "%LOG%" 2>&1 || bcdedit /set testsigning off >> "%LOG%" 2>&1
bcdedit /deletevalue nointegritychecks >> "%LOG%" 2>&1

echo. >> "%LOG%"
echo === after >> "%LOG%"
bcdedit /enum {current} >> "%LOG%" 2>&1
bcdedit | findstr /i "testsigning nointegritychecks" >> "%LOG%" 2>&1
if errorlevel 1 echo   (no testsigning / nointegritychecks entries left) >> "%LOG%"

echo. >> "%LOG%"
echo === remaining apex*/gdrv/msio services >> "%LOG%"
sc.exe query apexr >> "%LOG%" 2>&1
sc.exe query apexdrv >> "%LOG%" 2>&1

echo. >> "%LOG%"
echo === revert done %DATE% %TIME% >> "%LOG%"

echo.
echo revert finished, see revert.txt
if /i "%ARG%"=="reboot" (
  echo rebooting in 20s...
  timeout /t 20
  shutdown /r /t 0
) else (
  timeout /t 10
)
