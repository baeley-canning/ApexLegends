# temp\_probe22.ps1 -- PHASE 2: (only after a reboot) kdu+DSE-off, start apexdrv,
# run the 30-second phase2 (walk via MmCopyMemory -> cache -> bones), restore.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_probe22_console.txt"
"=== probe22 $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
Copy-Item "$root\temp\drv_backup\apexdrv.sys" 'C:\apexdrv.sys' -Force
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe start ApexDrv *>> $log
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_phase2.py" *>> $log
sc.exe stop ApexDrv *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 22 *>> $log
"=== done $(Get-Date -Format HH:mm:ss) ===" | Add-Content $log
