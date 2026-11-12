# h34v: wait for a fresh Apex process, settle, then run _p142.py --cal.
# PFN-lottery test: a fresh process gets fresh table PFNs; if the new DTB
# frame is not on the boot's dead-PFN set, cal passes.  Read-only probes only.
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_mk9_watch.log'
function W($s) { "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $s | Out-File $log -Append -Encoding utf8 }
"=== mk9 watcher $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log -Encoding utf8
W "watcher up, waiting for r5apex_dx12"
$proc = $null
for ($i = 0; $i -lt 180; $i++) {
    $proc = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { break }
    Start-Sleep -Seconds 10
}
if (-not $proc) { W "TIMEOUT: no game in 30 min"; exit 1 }
W "game pid=$($proc.Id) started=$($proc.StartTime) - settling 90s"
Start-Sleep -Seconds 90
if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { W "game died during settle"; exit 2 }
W "settled, running _p142.py --cal"
Set-Location 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
python _p142.py --cal 2>&1 | Out-File $log -Append -Encoding utf8
W "cal returned exit=$LASTEXITCODE"
