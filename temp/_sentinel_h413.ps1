# one-shot diagnostic sentinel v3 -- h414 edition
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Content -Path (Join-Path $root 'temp\_sentinel_ALIVE.txt') -Value ("entered " + (Get-Date -Format HH:mm:ss))
try {
$ps   = Get-Process python -ErrorAction SilentlyContinue |
        Select-Object Id, CPU, StartTime | Format-Table -AutoSize | Out-String
$tail = Get-Content (Join-Path $root 'temp\h414_live_walk_forensic.txt') -Tail 50 -ErrorAction SilentlyContinue | Out-String
$err  = Get-Content (Join-Path $root 'temp\h414_err.txt')  -Tail 12 -ErrorAction SilentlyContinue | Out-String
Set-Content -Path (Join-Path $root 'temp\_sentinel_h414.txt') -Encoding UTF8 -Value (
  "== PYTHON PROCS ==" + "`r`n" + $ps +
  "== H414 TXT TAIL ==" + "`r`n" + $tail +
  "== ERR TAIL ==" + "`r`n" + $err)
} catch { Set-Content -Path (Join-Path $root 'temp\_sentinel_ERR.txt') -Value ($_ | Out-String) }
$snap = Join-Path $root ('temp\_snaph414_' + (Get-Date -Format 'HHmmss') + '.txt')
Move-Item -Force (Join-Path $root 'temp\_sentinel_h414.txt') -Destination $snap -ErrorAction SilentlyContinue
Set-Content -Path (Join-Path $root 'temp\_sentinel_last.txt') -Value ("latest=" + $snap)

Set-Content -Path (Join-Path $root 'temp\_sentinel_DONE.txt') -Value ("done " + (Get-Date -Format HH:mm:ss))
exit 0
