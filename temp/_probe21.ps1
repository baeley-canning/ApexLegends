# temp\_probe21.ps1 -- stop DBUtilDrv2 (its residency kills the game), retry the
# driver load, run the dynamic probe16, restore.  THE run.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log = "$root\temp\_probe21_console.txt"
"=== probe21 $(Get-Date -Format HH:mm:ss) ===" | Set-Content $log
sc.exe stop DBUtilDrv2 *>> $log
sc.exe query DBUtilDrv2 *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 0 *>> $log
sc.exe start ApexDrv *>> $log
sc.exe query ApexDrv *>> $log
Start-Sleep -Seconds 1
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb16.py" *>> $log
sc.exe stop ApexDrv *>> $log
& 'C:\Users\Public\p37\kdu.exe' -prv 20 -dse 22 *>> $log
"=== done $(Get-Date -Format HH:mm:ss) ===" | Add-Content $log
