# p43h - read-only: resolve now auto-dumps hex on zero candidates.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43h_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME alive ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('HIT_CAP=' + ((Select-String -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Pattern '^HIT_CAP = (\d+)').Matches[0].Groups[1].Value))
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$prg = Join-Path $repo '_ritual\p40d_progress.txt'
if (Test-Path -LiteralPath $prg) { Move-Item -LiteralPath $prg -Destination (Join-Path $repo 'temp\p43g_progress.txt') -Force }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p40w_run.ps1', '--pid=5488'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
