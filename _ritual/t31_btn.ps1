# t31_btn.ps1 - locate the blue-outlined CREATE ACCOUNT button in a capture by colour.
# Writes image-space and screen-space centre (capture origin is always 40,20 - see shot_win).
param([string]$Png = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_t30_field.png',
      [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_t31_btn.txt')
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile($Png)
$bmp = New-Object System.Drawing.Bitmap $i.Width, $i.Height
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($i, 0, 0)
$minx = $bmp.Width; $maxx = -1; $miny = $bmp.Height; $maxy = -1
$y0 = [int]($bmp.Height * 0.62)
for ($y = $y0; $y -lt $bmp.Height; $y++) {
  for ($x = 0; $x -lt $bmp.Width; $x++) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.B -gt 190 -and $c.R -lt 110 -and $c.G -gt 70 -and $c.G -lt 160 -and $c.B - $c.R -gt 110) {
      if ($x -lt $minx) { $minx = $x }; if ($x -gt $maxx) { $maxx = $x }
      if ($y -lt $miny) { $miny = $y }; if ($y -gt $maxy) { $maxy = $y }
    }
  }
}
$g.Dispose(); $bmp.Dispose(); $i.Dispose()
if ($maxx -lt 0) { 'no blue found below 62%'; exit 1 }
$cx = [int](($minx + $maxx) / 2); $cy = [int](($miny + $maxy) / 2)
$L = @()
$L += "png=$Png"
$L += "box image: $minx,$miny .. $maxx,$maxy  (w $($maxx-$minx) h $($maxy-$miny))"
$L += "centre image: $cx,$cy"
$L += "click at screen: $($cx+40),$($cy+20)"
$L -join "`r`n" | Out-File -LiteralPath $Out -Encoding utf8
Write-Host "click $($cx+40),$($cy+20)"
