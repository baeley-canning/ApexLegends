# p43q - elevated read-only: p43o fixed the pid ladder (step 4) and un-skips
# multi-hit pages, so the page the old gate accepted (0x312862000) must finally
# be dumped, and --why splits "no PE" into a real verdict.  Same scan, same gate
# masks, same tail guard.  Only PID_OFFS / the hit loop / the why census changed.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43q_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME alive ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$src = Join-Path $repo 'ext\dumplive.py'
$L.Add('pid-offs=' + ((Select-String -LiteralPath $src -Pattern '^PID_OFFS = ').Matches[0].Value).Trim())
$L.Add('why-opt=' + ((Select-String -LiteralPath $src -Pattern '"why": ').Matches[0].Value).Trim())
$L.Add('hit-loop=' + [bool](Select-String -LiteralPath $src -Pattern 'hit=%d/%d'))
$L.Add('probe_dtb=' + [bool](Select-String -LiteralPath $src -Pattern 'def probe_dtb'))
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash)
$L.Add('drv(gio)=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } |
    ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('prev p40d dump=' + (Test-Path -LiteralPath (Join-Path $repo '_ritual\p40d_livedump.txt')))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$prg = Join-Path $repo '_ritual\p40d_progress.txt'
if (Test-Path -LiteralPath $prg) { Remove-Item -LiteralPath $prg -Force }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p43q_run.ps1', '--pid=5488', '--hex', '--why'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
