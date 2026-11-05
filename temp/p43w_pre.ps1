# p43w pre-state (R3).  Pure-read pid-anchored scan; the variable is the anchor
# (pid dword instead of the name string).  Records game, transport, hashes and
# the pid-offset lane list that will be tried.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43w_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME alive pid=5488 ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone pid=5488') }
$src = Join-Path $repo 'ext\pidscan.py'
foreach ($pat in '^PID = ', '^PID_OFFS = ', '^RAW_CAP = ', '^KEEP = ') {
    $ln = (Select-String -LiteralPath $src -Pattern $pat | Select-Object -First 1).Line
    $L.Add('const ' + $(if ($ln) { $ln.Trim() } else { 'MISSING ' + $pat }))
}
$L.Add('pidscan sha256=' + (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash)
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Algorithm SHA256).Hash)
$L.Add('drv(gio)=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } |
    ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('prev p43w out=' + (Test-Path -LiteralPath (Join-Path $repo '_ritual\p43w_pidscan.txt')))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$prg = Join-Path $repo '_ritual\p43w_progress.txt'
if (Test-Path -LiteralPath $prg) { Remove-Item -LiteralPath $prg -Force }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p43w_run.ps1', '--pid=5488'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
