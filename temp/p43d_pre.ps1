# p43d - pre-state read-back, then fire the single elevated p40w run.
# Read-only except: archives the crashed run's progress file and launches p40w (UAC prompt).
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43d_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME pid=5488 ws=$([int]($g.WorkingSet64/1MB))MB cpu=$([math]::Round($g.CPU))s start=$($g.StartTime.ToString('s')) responding=$($g.Responding)") } else { $L.Add('GAME pid=5488 GONE') }
foreach ($s in 'gdrv3', 'EAAntiCheatService', 'eaanticheat') {
    $L.Add(("svc {0} : {1}" -f $s, ((sc.exe query $s 2>&1 | Select-String 'STATE') -join ' ').Trim()))
}
$L.Add('blocklist=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -EA 0).VulnerableDriverBlocklistEnable)
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Algorithm SHA256).Hash)
$L.Add('badpa lines=' + (Get-Content -LiteralPath (Join-Path $repo '_ritual\p38_badpa.txt') -EA 0).Count)
$L.Add('OUT=' + [bool](Test-Path (Join-Path $repo '_ritual\p40d_livedump.txt')) + ' PREV=' + [bool](Test-Path (Join-Path $repo '_ritual\p40d_livedump.prev.txt')))
$L.Add('free C: = ' + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + ' GB')
$L.Add('whea18 total today-ish (last 12 h) = ' + (wevtutil qe System '/q:*[System[(EventID=18)]]' /c:20 /rd:true /f:text 2>&1 | Select-String 'Date:').Count)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8

$prg = Join-Path $repo '_ritual\p40d_progress.txt'
if (Test-Path -LiteralPath $prg) {
    Move-Item -LiteralPath $prg -Destination (Join-Path $repo 'temp\p43d_progress_crash2.txt') -Force
    Add-Content -LiteralPath $o -Value 'progress archived -> temp\p43d_progress_crash2.txt'
}
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p40w_run.ps1', '--pid=5488'
Add-Content -LiteralPath $o -Value ('LAUNCHED p40w pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
