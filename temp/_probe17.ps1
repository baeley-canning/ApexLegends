# temp\_probe17.ps1 -- elevated wrapper, full capture.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
"=== probe17 $(Get-Date -Format HH:mm:ss) ===" | Set-Content "$root\temp\_probe17_console.txt"
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb17.py" *>> "$root\temp\_probe17_console.txt"
"rc=$LASTEXITCODE" | Add-Content "$root\temp\_probe17_console.txt"
