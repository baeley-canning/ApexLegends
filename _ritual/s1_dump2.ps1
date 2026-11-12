# s1_dump2.ps1 - second split pass: unseen middles as fresh files + cur script copies.
$ws = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rt = Join-Path $ws '_ritual'
$l  = @(Get-Content -LiteralPath (Join-Path $rt 's1_wdk.out'))
$n  = $l.Count
$size = [Math]::Ceiling($n / 4)
for ($i = 0; $i -lt 4; $i++) {
  $from = $i * $size
  $to = [Math]::Min(($i + 1) * $size - 1, $n - 1)
  if ($from -le $to) { Set-Content -LiteralPath (Join-Path $rt ("s1_p{0}.txt" -f ($i + 1))) -Value $l[$from..$to] }
}
Copy-Item -LiteralPath (Join-Path $rt 'cur_h312_live.ps1') -Destination (Join-Path $rt 's1_cur312.txt') -Force
if (Test-Path (Join-Path $rt 's1.txt')) { Copy-Item -LiteralPath (Join-Path $rt 's1.txt') -Destination (Join-Path $rt 's1_notes.txt') -Force }
$drv = Join-Path $ws 'QwenKernPremium\driver\apexdrv.c'
$d = @(Get-Content -LiteralPath $drv)
Set-Content -LiteralPath (Join-Path $rt 's1_drv_end.txt') -Value $d[1994..($d.Count - 1)]
Add-Content -LiteralPath (Join-Path $rt 's1_diag.txt') -Value ("dump2 " + (Get-Date -Format 'HH:mm:ss') + " parts=4 n=" + $n + " drv=" + $d.Count)
