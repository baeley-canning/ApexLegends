# temp\_probe18.ps1 -- cameo: DSE off, start ApexDrv (service exists; its .sys is on
# C:\ from the earlier attempt), run probe17 which now has drv_phys as the dead-page
# fallback, then stop + restore DSE.  One UAC.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_probe18_console.txt"
"=== probe18 $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
"apexdrv.sys on C:\: $(Test-Path 'C:\apexdrv.sys')" | Add-Content $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe start ApexDrv *>> $log
sc.exe query ApexDrv *>> $log
Start-Sleep -Seconds 1
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb17.py" *>> $log
sc.exe stop ApexDrv *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 22 *>> $log
"=== done $(Get-Date -Format HH:mm:ss) ===" | Add-Content $log
