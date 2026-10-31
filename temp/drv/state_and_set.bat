@echo off
rem Collect signing state and turn on test signing (now that Secure Boot is off).
setlocal
set LOG=C:\Users\New User\OneDrive\Desktop\cheating\temp\drv\state.txt
set SYS=C:\Users\New User\OneDrive\Desktop\cheating\temp\drv\apexr.sys

> "%LOG%" echo === secureboot
>> "%LOG%" powershell -NoProfile -Command "try{'SecureBoot=' + (Confirm-SecureBootUEFI)}catch{'SecureBoot=unknown'}" 2>&1
>> "%LOG%" echo === bcdedit before
>> "%LOG%" bcdedit /enum {current} 2>&1 | findstr /i "testsigning nointegritychecks path"
>> "%LOG%" echo === enable testsigning
>> "%LOG%" bcdedit /set testsigning on 2>&1
>> "%LOG%" echo === bcdedit after
>> "%LOG%" bcdedit /enum {current} 2>&1 | findstr /i "testsigning nointegritychecks"
>> "%LOG%" echo === cert stores
>> "%LOG%" certutil -store Root ApexR 2>&1 | findstr /i "ApexR D33ED7478345A1F373111F13439DC34D76C96D55"
>> "%LOG%" certutil -store TrustedPublisher ApexR 2>&1 | findstr /i "ApexR D33ED7478345A1F373111F13439DC34D76C96D55"
>> "%LOG%" echo === driver file
>> "%LOG%" dir C:\Windows\System32\drivers\apexr.sys 2>&1 | findstr /i apexr
>> "%LOG%" echo === service
>> "%LOG%" sc qc apexr 2>&1
>> "%LOG%" sc query apexr 2>&1
>> "%LOG%" echo === done
