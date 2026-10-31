@echo off
rem Step 1 of 2 (after Secure Boot is disabled in the BIOS): turn on test
rem signing.  Takes effect on the next boot.
setlocal
bcdedit /set testsigning on
if errorlevel 1 (
  echo FAILED - Secure Boot is probably still on. Disable it in the BIOS first.
  exit /b 1
)
bcdedit /enum {current} | findstr /i "testsigning"
echo OK - reboot now, then run after_reboot.bat
