# temp\_cameo.ps1 -- the whole apexdrv cameo, self-logging. Run elevated via -File.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_cameo_log.txt"
"=== cameo $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
sc.exe delete ApexDrv *>> $log
Start-Sleep -Seconds 1
Copy-Item "$root\temp\drv_backup\apexdrv.sys" 'C:\apexdrv.sys' -Force
"copied: $(Test-Path 'C:\apexdrv.sys')" | Add-Content $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe create ApexDrv type= kernel start= demand binPath= C:\apexdrv.sys *>> $log
sc.exe start ApexDrv *>> $log
sc.exe query ApexDrv *>> $log
Start-Sleep -Seconds 1
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb13.py" *>> $log
sc.exe stop ApexDrv *>