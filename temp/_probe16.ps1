# temp\_probe16.ps1 -- elevated wrapper, full capture.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
"=== probe16 $(Get-Date -Format HH:mm:ss) ===" | Set-Content "$root\temp\_probe16_console.txt"
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb16.py" *>> "$root\temp\_probe16_console.txt"
"rc=$LASTEXITCODE" | Add-Content "$root\temp\_probe16_console.txt"
