@echo off
rem Build apexr.sys with the BuildTools compiler + WDK 10.0.26100 kernel headers.
setlocal
set WDK=C:\Program Files (x86)\Windows Kits\10
set SDKDIR=%WDK%\Include\10.0.26100.0
set KMLIB=%WDK%\Lib\10.0.26100.0\km\x64
set MSVC=C:\BuildTools\VC\Tools\MSVC\14.44.35207
set CLPATH=%MSVC%\bin\Hostx64\x64\cl.exe
set LINKPATH=%MSVC%\bin\Hostx64\x64\link.exe
cd /d "%~dp0"

"%CLPATH%" /nologo /c /O2 /GS- /kernel /D_AMD64_ /DAMD64 /D_WIN64 /DWIN32=100 ^
  /I"%SDKDIR%\km" /I"%SDKDIR%\shared" /I"%SDKDIR%\ucrt" /I"%MSVC%\include" ^
  /Foapexr.obj apexr.c
if errorlevel 1 goto :fail

"%LINKPATH%" /nologo /DRIVER /SUBSYSTEM:NATIVE /MACHINE:X64 /ENTRY:DriverEntry ^
  /OUT:apexr.sys /NODEFAULTLIB apexr.obj ^
  "%KMLIB%\ntoskrnl.lib" "%KMLIB%\BufferOverflowK.lib" "%KMLIB%\hal.lib"
if errorlevel 1 goto :fail

echo BUILD OK
dir /b apexr.sys
exit /b 0

:fail
echo BUILD FAILED
exit /b 1
