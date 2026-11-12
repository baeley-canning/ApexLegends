@echo off
if not exist "C:\Users\New User\OneDrive\Desktop\cheating\temp\drv_backup" mkdir "C:\Users\New User\OneDrive\Desktop\cheating\temp\drv_backup"
move /Y "C:\WINDOWS\System32\drivers\apexdrv*" "C:\Users\New User\OneDrive\Desktop\cheating\temp\drv_backup\" > "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm2.txt" 2>&1
dir "C:\WINDOWS\System32\drivers\apexdrv*" >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm2.txt" 2>&1
sc query zapexdrv >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm2.txt" 2>&1
sc query kernprobe >> "C:\Users\New User\OneDrive\Desktop\cheating\temp\_drvrm2.txt" 2>&1
