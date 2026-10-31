@echo off
setlocal enabledelayedexpansion

echo ================================================
echo  ApexDrv Driver Setup (VM)
echo ================================================
echo.

REM Step 1: Import certificate into Root store
echo [1/5] Importing apexcert.cer into Root store...
powershell -NoProfile -Command "Import-Certificate -FilePath 'C:\apexcert.cer' -CertStoreLocation Cert:\LocalMachine\Root" >nul 2>&1
if errorlevel 1 (
    echo  FAILED. Run as admin.
    pause
    exit /b 1
)
echo  OK

REM Step 2: Import certificate into TrustedPublisher store
echo [2/5] Importing apexcert.pfx into TrustedPublisher store...
powershell -NoProfile -Command "Import-PfxCertificate -FilePath 'C:\apexcert.pfx' -CertStoreLocation Cert:\LocalMachine\TrustedPublisher -Password (ConvertTo-SecureString -String 'temp1234' -Force -AsPlainText)" >nul 2>&1
if errorlevel 1 (
    echo  FAILED. Run as admin. Check PFX password.
    pause
    exit /b 1
)
echo  OK

REM Step 3: Copy driver to System32\drivers
echo [3/5] Copying apexdrv.sys to C:\Windows\System32\drivers\...
copy /y C:\apexdrv.sys C:\Windows\System32\drivers\apexdrv.sys >nul
if errorlevel 1 (
    echo  FAILED. Run as admin.
    pause
    exit /b 1
)
echo  OK

REM Step 4: Enable test signing
echo [4/5] Enabling test signing...
bcdedit /set {current} testsigning >nul 2>&1
if errorlevel 1 (
    echo  FAILED. Run as admin.
    pause
    exit /b 1
)
echo  OK

REM Step 5: Verify
echo [5/5] Verifying...
echo.
echo --- Certificate in stores ---
certutil -verify C:\apexcert.cer >nul 2>&1 && echo Cert: VALID || echo Cert: INVALID
bcdedit /enum {current} | findstr /i testsigning
echo.
echo ================================================
echo SETUP COMPLETE
echo Reboot required for test signing to take effect
echo After reboot, run: sc start apexdrv
echo ================================================
