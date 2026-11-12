$r='C:\Users\New User\OneDrive\Desktop\cheating'
$py='C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$s=Join-Path $r 'temp\h401_kva_inner.ps1'
@"
`$ErrorActionPreference = 'Continue'
& '$py' '$r\temp\h401_run.py' *>> '$r\temp\h401_console2.txt'
"@ | Set-Content -LiteralPath $s -Encoding ASCII
Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$s+'"') -Wait