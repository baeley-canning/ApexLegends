# temp\_probe15.ps1 -- elevated wrapper, full capture.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
"=== probe15 $(Get-Date -Format HH:mm:ss) ===" | Set-Content "$root\temp\_probe15_console.txt"
& 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe' "$root\temp\_qk_dtb15.py" *>> "$root\temp\_probe15_console.txt"
"rc=$LASTEXITCODE" | Add-Content "$root\temp\_probe15_console.txt"
