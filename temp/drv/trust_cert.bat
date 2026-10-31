@echo off
rem Trust the test cert so the driver's chain validates (belt and braces for
rem test signing) and re-verify the stores.
setlocal
set LOG=C:\Users\New User\OneDrive\Desktop\cheating\temp\drv\trust.txt
set CER=C:\Users\New User\OneDrive\Desktop\cheating\temp\drv\apexr.cer

> "%LOG%" echo === add Root
>> "%LOG%" certutil -addstore -f Root "%CER%" 2>&1
>> "%LOG%" echo === add TrustedPublisher
>> "%LOG%" certutil -addstore -f TrustedPublisher "%CER%" 2>&1
>> "%LOG%" echo === verify Root
>> "%LOG%" certutil -store Root ApexR 2>&1 | findstr /i "ApexR"
>> "%LOG%" echo === verify TrustedPublisher
>> "%LOG%" certutil -store TrustedPublisher ApexR 2>&1 | findstr /i "ApexR"
>> "%LOG%" echo === done
