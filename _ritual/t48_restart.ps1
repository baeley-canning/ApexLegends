# t48_restart.ps1 - clean restart of the EA app after the restore-all-windows step left it on a
# blank helper window. Kills EADesktop, waits, relaunches, then waits for a titled window.
$exe = 'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
Get-Process -Name 'EADesktop' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 4
Start-Process -FilePath $exe | Out-Null
$win = $null
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 2
  $win = Get-Process -Name 'EADesktop' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | Select-Object -First 1
  if ($win) { break }
}
if ($win) { "relaunched pid=$($win.Id) title=[$($win.MainWindowTitle)] after $($i*2)s" | Set-Content -LiteralPath "$r\_t48.txt" -Encoding utf8 }
else { 'relaunched but no titled window within 60s' | Set-Content -LiteralPath "$r\_t48.txt" -Encoding utf8 }
