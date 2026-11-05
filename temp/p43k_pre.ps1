# p43k - elevated read-only probe: head window widened to -0x600.
# p43i put a candidate through the PCID-masked gate but its DTB lane read a kernel
# VA and the walk found no PE.  A pid 0x088 below the name is +0x440 from a base
# only if ImageFileName sits at +0x4c8; at +0x5a8 the DTB moves to hit-0x580 and
# a 0x4e0 window never saw it.  Same gate, same scan, head window only.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43k_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME alive ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('HEX_WIN=' + ((Select-String -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Pattern '^HEX_WIN = .+').Matches[0].Value))
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\dumplive.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$prg = Join-Path $repo '_ritual\p40d_progress.txt'
if (Test-Path -LiteralPath $prg) { Move-Item -LiteralPath $prg -Destination (Join-Path $repo 'temp\p43i_progress.txt') -Force }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p40w_run.ps1', '--pid=5488', '--hex'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
