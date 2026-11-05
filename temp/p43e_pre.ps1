# p43e - second (and last) attempt: base model fixed, pre-state re-read, then fire p40w.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43e_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME pid=5488 ws=$([int]($g.WorkingSet64/1MB))MB start=$($g.StartTime.ToString('s')) responding=$($g.Responding) title='$($g.MainWindowTitle)'") } else { $L.Add('GAME gone') }
foreach ($s in 'gdrv3', 'EAAntiCheatService', 'eaanticheat') {
    $L.Add(("svc {0} : {1}" -f $s, ((sc.exe query $s 2>&1 | Select-String 'STATE') -join ' ').Trim()))
}
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Algorithm SHA256).Hash)
$L.Add('OUT=' + [bool](Test-Path (Join-Path $repo '_ritual\p40d_livedump.txt')) + ' PREV=' + [bool](Test-Path (Join-Path $repo '_ritual\p40d_livedump.prev.txt')))
$L.Add('free C: = ' + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + ' GB')
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; Get-Content -LiteralPath $o; exit 2 }

$prg = Join-Path $repo '_ritual\p40d_progress.txt'
if (Test-Path -LiteralPath $prg) {
    Move-Item -LiteralPath $prg -Destination (Join-Path $repo 'temp\p43d_progress_nocr3.txt') -Force
    Add-Content -LiteralPath $o -Value 'progress archived -> temp\p43d_progress_nocr3.txt'
}
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p40w_run.ps1', '--pid=5488'
Add-Content -LiteralPath $o -Value ('LAUNCHED p40w pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
