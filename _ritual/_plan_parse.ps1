# _plan_parse.ps1 - parse-check k10_soak.ps1 (no execution)
$f = 'C:\p37vm\payload\k10_soak.ps1'
$o = Join-Path $PSScriptRoot '_plan_parse.txt'
$e = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
"file=$f lines=$((Get-Content $f).Count) errors=$($e.Count)" | Set-Content -Encoding ascii $o
$e | ForEach-Object { "  L$($_.Extent.StartLineNumber): $($_.Message)" } | Add-Content -Encoding ascii $o
