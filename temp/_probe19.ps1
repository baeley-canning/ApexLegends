# temp\_probe19.ps1 -- driver load attempt with a FRESH service record + DSE off,
# then validate the known object.  If the loader refuses, try DirectIo64 as a map.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_probe19_console.txt"
"=== probe19 $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
Copy-Item "$root\temp\drv_backup\apexdrv.sys" 'C:\apexdrv.sys' -Force
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe delete ApexDrv *>> $log
Start-Sleep -Seconds 1
sc.exe create ApexDrv type= kernel start= demand binPath= C:\apexdrv.sys *>> $log
sc.exe start ApexDrv *>> $log
sc.exe query ApexDrv *>> $log
Start-Sleep -Seconds 1
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb17.py" *>> $log
sc.exe stop ApexDrv *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 22 *>> $log
"=== done $(Get-Date -Format HH:mm:ss) ===" | Add-Content $log
