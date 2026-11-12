# One fresh RAM-map-bounded name sweep, new output only (R5).
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$runner = Join-Path $root 'temp\_h392_fresh_inner.ps1'
@"
& '$py' '$root\temp\_h392_stage0.py' '--pid=14008' '--fresh' '--new' '--no-elevate' *> '$root\temp\_h392_fresh_console.txt'
`$LASTEXITCODE | Set-Content '$root\temp\_h392_fresh_rc.txt'
"@ | Set-Content -LiteralPath $runner -Encoding ASCII
"start=$(Get-Date -Format o)" | Set-Content $root\temp\_h392_fresh_start.txt
$p = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '"') -Verb RunAs -Wait -PassThru
"parent_rc=$($p.ExitCode)" | Set-Content $root\temp\_h392_fresh_parent_rc.txt