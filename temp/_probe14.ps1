# temp\_probe14.ps1 -- elevated wrapper with full capture (the raw -Command child
# silently wedged at 04:58; this pattern has never failed).
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
"=== probe14 $(Get-Date -Format HH:mm:ss) ===" | Set-Content "$root\temp\_probe14_console.txt"
sc.exe stop DBUtilDrv2 *>> "$root\temp\_probe14_console.txt"
Start-Sleep -Seconds 2
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb14.py" *>> "$root\temp\_probe14_console.txt"
"rc=$LASTEXITCODE" | Add-Content "$root\temp\_probe14_console.txt"
