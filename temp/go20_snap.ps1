param([string]$Suffix = 'snap')
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$vout = Join-Path $base 'qk_va_20261120_171652.txt'
$cons = Join-Path $base 'qk_va_console.txt'
$watc = Join-Path $base '_go20_watch.txt'
$feed = Join-Path $base 'qk_feed.json'
$dest = Join-Path $base ('_go20_' + $Suffix + '.txt')
$L = @()
$em = Get-Process -Id 10304 -ErrorAction SilentlyContinue
if ($em) { $L += ('EMIT cpu={0}s alive=True' -f [math]::Round($em.CPU,1)) } else { $L += 'EMIT alive=False' }
if (Test-Path $vout) {
  $vi = Get-Item $vout
  $L += ('OUT bytes={0} mtime={1}' -f $vi.Length, $vi.LastWriteTime.ToString('HH:mm:ss'))
  $L += (Get-Content $vout -Tail 12)
} else { $L += 'OUT missing' }
try {
  $j = Get-Content $feed -Raw | ConvertFrom-Json
  $L += ('FEED prod={0} ents={1} why={2}' -f $j.meta.producer, @($j.ents).Count, $j.meta.ents_reason)
} catch { $L += 'FEED unparseable' }
$L += (Get-Content $watc -Tail 3)
$L += (Get-Content $cons -Tail 6)
Set-Content -Path $dest -Value $L
Write-Output ('SNAPPED ' + $dest)
