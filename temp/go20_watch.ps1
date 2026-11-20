# go20_watch.ps1 - single-writer telemetry for the go20 sitting (appends only)
$ErrorActionPreference = 'SilentlyContinue'
$t = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out = Join-Path $t '_go20_watch.txt'
$feed = Join-Path $t 'qk_feed.json'
Add-Content $out ('=== go20 watch start {0} ===' -f (Get-Date -Format s))
for ($i = 0; $i -lt 100; $i++) {
  $ln = '{0} r{1:D2}' -f (Get-Date -Format HH:mm:ss), $i
  $gp = Get-Process r5apex_dx12 -EA SilentlyContinue
  if ($gp) { $ln += ' | game pid={0} resp={1}' -f $gp.Id, $gp.Responding } else { $ln += ' | game ABSENT' }
  if (Test-Path $feed) {
    $fi = Get-Item $feed
    $age = [math]::Round(((Get-Date) - $fi.LastWriteTime).TotalSeconds, 1)
    try {
      $j = Get-Content $feed -Raw | ConvertFrom-Json
      $ln += ' | feed age={0}s ents={1} prod={2} why={3}' -f $age, @($j.ents).Count, $j.meta.producer, $j.meta.ents_reason
    } catch { $ln += ' | feed unparseable size={0}B' -f $fi.Length }
  } else { $ln += ' | feed MISSING' }
  $pys = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue
  $pl = (@($pys) | ForEach-Object { '{0}' -f $_.ProcessId }) -join ','
  $ln += ' | py[' + $pl + ']'
  Add-Content $out $ln
  Start-Sleep -Seconds 5
}
Add-Content $out ('=== go20 watch end {0} ===' -f (Get-Date -Format s))
