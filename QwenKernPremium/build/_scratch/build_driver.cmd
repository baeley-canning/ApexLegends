@echo off
setlocal

:: Build apexdrv.sys using cl.exe + link.exe (WDK MSBuild targets not required)
:: Requires an elevated Developer Command Prompt or vcvars64.bat sourced beforehand.
:: Uses short path to avoid "unrecognized source file type" bug with spaces in user names.

set KM_INC=C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\km
set KM_CRT=%KM_INC%\crt
set UM_INC=C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um
set SHARED_INC=C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared
set KM_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\km\x64

:: Hardcoded short path — avoids cl.exe space-in-path bug
set DRVR_DIR=C:\Users\NEWUSE~1\OneDrive\Desktop\cheating\QwenKernPremium
set SRC=%DRVR_DIR%\driver\apexdrv.c
set OBJ=%DRVR_DIR%\driver\apexdrv.obj
set OUT=%DRVR_DIR%\build\apexdrv.sys

:: Ensure output dir exists
if not exist "%DRVR_DIR%\build" mkdir "%DRVR_DIR%\build"

:: Clean previous artifacts
if exist "%OBJ%" del /f /q "%OBJ%"
if exist "%OUT%" del /f /q "%OUT%"

echo [1/2] Compiling apexdrv.c ...
C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\cl.exe /c /D_AMD64_ /DPOOL_NX_OPTIN=1 /DNDEBUG /Zi /W3 /nologo /O2 /Fo:"%OBJ%" /I"%DRVR_DIR%\driver\..\include" /I"%KM_INC%" /I"%KM_CRT%" /I"%SHARED_INC%" /I"%UM_INC%" "%SRC%"
if errorlevel 1 (
    echo COMPILATION FAILED
    exit /b %errorlevel%
)
if not exist "%OBJ%" (
    echo COMPILATION FAILED - no obj produced
    exit /b 1
)

echo [2/2] Linking apexdrv.sys ...
C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\link.exe /NOLOGO /DRIVER /SUBSYSTEM:NATIVE /ENTRY:DriverEntry /NODEFAULTLIB /OUT:"%OUT%" "%OBJ%" ntoskrnl.lib hal.lib BufferOverflowK.lib /LIBPATH:"%KM_LIB%"
if errorlevel 1 (
    echo LINKING FAILED
    exit /b %errorlevel%
)

if not exist "%OUT%" (
    echo LINKING FAILED - no sys produced
    exit /b 1
)

echo BUILD OK: %OUT% (8704 bytes)
exit /b 0
