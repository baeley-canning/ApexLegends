@echo off
setlocal

echo [1/4] Importing apexcert into Root store...
certutil -addstore Root C:\temp_sign\apexcert.cer >nul 2>&1
if errorlevel 1 (
    echo  ERROR: Failed to import into Root store. Run as admin.
    exit /b 1
)
echo  OK: apexcert in Root

echo [2/4] Importing apexcert into TrustedPublisher store...
certutil -addstore TrustedPublisher C:\temp_sign\apexcert.pfx >nul 2>&1
if errorlevel 1 (
    echo  ERROR: Failed to import into TrustedPublisher. Run as admin.
    exit /b 1
)
echo  OK: apexcert in TrustedPublisher

echo [3/4] Enabling test signing...
bcdedit /set {current} testsigning >nul 2>&1
if errorlevel 1 (
    echo  ERROR: bcdedit failed. Run as admin.
    exit /b 1
)
echo  OK: testsigning enabled

echo [4/4] Verifying...
certutil -verify C:\temp_sign\apexcert.cer >nul 2>&1
bcdedit /enum {current} | findstr /i testsigning
echo.
echo ============================================
echo DONE. Reboot now: shutdown /r /t 0
echo After reboot, run: sc start apexdrv
echo ============================================
