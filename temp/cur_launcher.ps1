# cur.ps1 -- one-line launcher. The tick re-fetches this, but a previous run can still hold it
# open, so once.cmd's delete fails and the OLD cur.ps1 is re-run (measured 11:27: payload had the
# new fields, the run printed none). This launcher therefore never carries logic itself: it always
# downloads a *freshly named* copy of the real probe, which can neither be stale nor locked.
$n = Join-Path $env:TEMP ('p97b_' + (Get-Random) + '.ps1')
try { (New-Object Net.WebClient).DownloadFile('http://10.0.2.2:8080/p97b.ps1', $n) } catch { exit 1 }
& powershell -NoProfile -ExecutionPolicy Bypass -File $n
