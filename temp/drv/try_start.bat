@echo off
rem Try to load apexr right now (works only if the current boot already allows
rem test signing -- otherwise this fails with 577 and a reboot is required).
setlocal
set T=C:\Users\New User\OneDrive\Desktop\cheating\temp
set LOG=%T%\drv\try_start.txt
> "%LOG%" echo === try start
>> "%LOG%" sc start apexr 2>&1
>> "%LOG%" sc query apexr 2>&1
>> "%LOG%" echo === game
>> "%LOG%" tasklist /fi "imagename eq r5apex_dx12.exe" 2>&1
>> "%LOG%" echo === selftest
call "%T%\run_kx.bat" --selftest
>> "%LOG%" type "%T%\kx_console.txt"
>> "%LOG%" echo === done
type "%LOG%"
