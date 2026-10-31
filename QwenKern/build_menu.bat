@echo off
rem ---------------------------------------------------------------------------
rem  build_menu.bat -- builds ApexCheatMenu.exe using the locally installed
rem  MSVC build tools.  No third-party dependencies are required.
rem ---------------------------------------------------------------------------
setlocal
set "VCVARS=C:\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

if not exist "%VCVARS%" (
    echo [ERROR] vcvars64.bat not found at "%VCVARS%"
    exit /b 1
)

call "%VCVARS%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] failed to initialise the MSVC environment
    exit /b 1
)

set "SRCDIR=%~dp0phase3_menu_system\imgui_integration"
pushd "%SRCDIR%" || (
    echo [ERROR] source directory not found: "%SRCDIR%"
    exit /b 1
)

if not exist Release mkdir Release

echo [BUILD] compiling ApexCheatMenu.exe ...
cl /nologo /EHsc /O2 /MD /W3 /DNDEBUG /std:c++17 ^
   /I"..\..\phase4_esp_overlay" ^
   /Fo:"Release\\" /Fe:"Release\ApexCheatMenu.exe" ^
   main.cpp menu_core.cpp esp_gdi.cpp ..\..\phase4_esp_overlay\entity_extractor.cpp ^
   /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib

set "RC=%ERRORLEVEL%"
popd

if "%RC%"=="0" (
    echo [OK] Build succeeded -^> "%SRCDIR%\Release\ApexCheatMenu.exe"
) else (
    echo [ERROR] Build failed with code %RC%
)

endlocal & exit /b %RC%
