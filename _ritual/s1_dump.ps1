# s1_dump.ps1 - split s1_wdk.out + snapshot exact source regions for Stage-1 edits.
# Fresh output files => clean full reads. Read-only wrt everything else.
$ws  = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rt  = Join-Path $ws '_ritual'
function Dump($src, $from, $to, $dst) {
  if (-not (Test-Path $src)) { Set-Content -LiteralPath $dst -Value "MISSING $src"; return }
  $l = @(Get-Content -LiteralPath $src)
  $n = $l.Count
  if ($from -lt 1) { $from = 1 }
  if ($to -gt $n)  { $to = $n }
  if ($from -gt $to) { $from = $to }
  $body = @("### SRC $src  lines $from..$to of $n")
  $body += @($l[($from-1)..($to-1)])
  Set-Content -LiteralPath $dst -Value $body
}

$w = Join-Path $rt 's1_wdk.out'
$l = @(Get-Content -LiteralPath $w)
Set-Content -LiteralPath (Join-Path $rt 's1_a.txt') -Value $l[0..244]
Set-Content -LiteralPath (Join-Path $rt 's1_b.txt') -Value $l[245..489]
Set-Content -LiteralPath (Join-Path $rt 's1_c.txt') -Value $l[490..($l.Count-1)]

$drv = Join-Path $ws 'QwenKernPremium\driver\apexdrv.c'
Dump $drv   1  140  (Join-Path $rt 's1_drv_head.txt')
Dump $drv 1755 1880  (Join-Path $rt 's1_drv_probe.txt')
Dump $drv 1920 2000  (Join-Path $rt 's1_drv_tail.txt')

$hdr = Join-Path $ws 'QwenKernPremium\include\apex_driver_ioctl.h'
Dump $hdr   1  170  (Join-Path $rt 's1_hdr_top.txt')
Dump $hdr 160  340  (Join-Path $rt 's1_hdr_mid.txt')

$diag = Join-Path $rt 's1_diag.txt'
Set-Content -LiteralPath $diag -Value @(
  ("s1_diag " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
  ("s1_wdk.out lines=" + $l.Count),
  ("apexdrv.c lines=" + @(Get-Content -LiteralPath $drv).Count),
  ("header lines=" + @(Get-Content -LiteralPath $hdr).Count)
)
Get-ChildItem $rt -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^cur' } | ForEach-Object { Add-Content -LiteralPath $diag -Value ("curfile: " + $_.Name) }
Get-ChildItem $rt -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^h3[23]' } | ForEach-Object { Add-Content -LiteralPath $diag -Value ("h3file: " + $_.Name) }

$cur = Get-ChildItem $rt -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^cur.*\.ps1$' } | Select-Object -First 1
if ($cur) { Copy-Item -LiteralPath $cur.FullName -Destination (Join-Path $rt 's1_cur.txt') -Force }

$bld = Join-Path $rt '_h518_drvbuild.ps1'
if (Test-Path $bld) { Copy-Item -LiteralPath $bld -Destination (Join-Path $rt 's1_build.txt') -Force }
Add-Content -LiteralPath $diag -Value ("DONE " + (Get-Date -Format 'HH:mm:ss'))
