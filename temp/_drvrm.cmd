@echo off
sc stop ApexDrv > "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm.txt" 2>&1
sc delete ApexDrv >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm.txt" 2>&1
if exist "C:\WINDOWS\System32\drivers\apexdrv.sys" move /Y "C:\WINDOWS\System32\drivers\apexdrv.sys" "C:\Users\New User\OneDrive\Desktop\cheating\temp\apexdrv.sys.staged" >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm.txt" 2>&1
sc query ApexDrv >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm.txt" 2>&1
dir "C:\WINDOWS\System32\drivers\apexdrv*" >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm.txt" 2>&1
