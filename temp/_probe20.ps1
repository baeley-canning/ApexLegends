# temp\_probe20.ps1 -- DSE off -> start driver -> DYNAMIC probe16 (sweep+object+walk
# with drv_phys fallback) -> restore.  The last moving part.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_probe20_console.txt"
"=== probe20 $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
Copy-Item "$root\temp\drv_backup\apexdrv.sys" 'C:\apexdrv.sys' -Force
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe delete ApexDrv *>> $log
Start-Sleep -Seconds 1
sc.exe create ApexDrv type= kernel start= demand binPath= C:\apexdrv.sys *>> $log
sc.exe start ApexDrv *>> $log
sc.exe query ApexDrv *>> $log
Start-Sleep -Seconds 1
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb16.py" *>> $log
sc.exe stop ApexDrv *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 22 *>> $log
"=== done $(Get-Date -Format HH:mm:ss) ===" | Add-Content $log
