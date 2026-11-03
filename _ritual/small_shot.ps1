# small_shot - capture the desktop and immediately downscale it, so the png is small enough to read.
# shot_desk.ps1 always writes 4+ MB at native resolution and ignores -Out; this wraps it.
param([double]$Scale = 0.5)
Add-Type -AssemblyName System.Drawing
$rit = $PSScriptRoot
$raw = Join-Path $rit 'shot_desk.png'
$out = Join-Path $rit 'd_small.png'
& (Join-Path $rit 'shot_desk.ps1') | Out-Null
if(-not (Test-Path -LiteralPath $raw)){ 'capture failed'; exit 1 }
$s = [System.Drawing.Image]::FromFile($raw)
$w = [Math]::Max(1,[int]($s.Width * $Scale)); $h = [Math]::Max(1,[int]($s.Height * $Scale))
$b = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($s, 0, 0, $w, $h)
$b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose(); $s.Dispose()
'saved ' + $out + ' ' + $w + 'x' + $h