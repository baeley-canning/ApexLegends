@echo off
rem Registers + fires a one-shot task that runs run_sysprobe.bat as LOCAL SYSTEM.
rem Must itself run elevated.
set LOG=%TEMP%\cline_sysprobe_task.txt
schtasks /create /tn ClineSysProbe /tr "\"C:\Users\New User\OneDrive\Desktop\cheating\temp\run_sysprobe.bat\"" /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f > "%LOG%" 2>&1
schtasks /run /tn ClineSysProbe >> "%LOG%" 2>&1
ping -n 20 127.0.0.1 > nul
schtasks /query /tn ClineSysProbe /fo list >> "%LOG%" 2>&1
type "%LOG%"
