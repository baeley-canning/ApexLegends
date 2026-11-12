# h392 transport gate. Read-only; pre/post process and service state is evidence.
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$log = Join-Path $root 'temp\_h392_run.txt'
"pre $(Get-Date -Format o)" | Set-Content $log
Get-Process -Id 14008 -ErrorAction SilentlyContinue | Format-List Id,ProcessName,StartTime | Out-String | Add-Content $log
sc.exe query gdrv3 2>&1 | Out-String | Add-Content $log
$script = Join-Path $root 'temp\_h392_stage0.py'
$innerLog = Join-Path $root 'temp\_h392_elevated.txt'
$runner = Join-Path $root 'temp\_h392_inner.ps1'
@"
`$ErrorActionPreference = 'Continue'
& '$py' '$script' '--pid=14008' '--no-elevate' *> '$innerLog'
`$LASTEXITCODE | Set-Content '$root\temp\_h392_rc.txt'
"@ | Set-Content -LiteralPath $runner -Encoding ASCII
$arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '"'
$p = Start-Process -FilePath powershell.exe -ArgumentList $arg -Verb RunAs -Wait -PassThru
"parent_rc=$($p.ExitCode)" | Add-Content $log
"post $(Get-Date -Format o)" | Add-Content $log
Get-Process -Id 14008 -ErrorAction SilentlyContinue | Format-List Id,ProcessName | Out-String | Add-Content $log
sc.exe query gdrv3 2>&1 | Out-String | Add-Content $log