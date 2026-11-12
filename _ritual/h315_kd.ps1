# h315_kd.ps1 - kd !analyze -v against the temp copy of the 21:33:46 dump.
# Unelevated on purpose: the dump copy lives in the tree and the symbol cache is user-writable,
# so nothing here needs admin (the 0xDA dump itself was copied by h315_dump.ps1, elevated).
# R5: keeps the failed -c attempt as h315_kd_usage.out, writes fresh h315_kd.out + h315_kd_run.out.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dmp = Join-Path (Split-Path -Parent $here) 'temp\110626-10609-01.dmp'
$cf  = Join-Path $here 'h315_kd.txt'
$out = Join-Path $here 'h315_kd.out'
$run = Join-Path $here 'h315_kd_run.out'
$kd  = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $run -Value ($L -join "`r`n") -Encoding UTF8 }
Lg '===== h315 kd ====='
Lg ('dmp exists=' + (Test-Path $dmp) + ' kd=' + (Test-Path $kd) + ' cf=' + (Test-Path $cf))
if (Test-Path $out) { Move-Item -LiteralPath $out -Destination (Join-Path $here 'h315_kd_usage.out') -Force -EA 0; Lg 'previous h315_kd.out kept as h315_kd_usage.out' }
$env:_NT_SYMBOL_PATH = 'srv*C:\Users\New User\symbols*https://msdl.microsoft.com/download/symbols'
try {
    # one argument string, not an array: Start-Process re-splits arrays and the symbol path
    # "C:\Users\New User\symbols" then arrives as two switches. Symbols come from the env var.
    $a = '-z "' + $dmp + '" -cf "' + $cf + '"'
    $p = Start-Process $kd -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
    if (-not $p.WaitForExit(280000)) { Lg 'TIMEOUT 280s'; try { $p.Kill() } catch { } }
    else { Lg ('rc=' + $p.ExitCode) }
} catch { Lg ('ERR: ' + $_.Exception.Message) }
Emit
Lg ('out-bytes=' + (Get-Item $out -EA 0).Length)
Emit
