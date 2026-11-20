# t60_shot.ps1 - focus a pid's window (optional size), then capture it via desktop crop.
# Usage: t60_shot.ps1 -TargetPid N -Tag x [-W 1280 -H 940]
param([int]$TargetPid = 0, [string]$Tag = 't60', [int]$W = 1280, [int]$H = 940)
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
if (-not $TargetPid) { $TargetPid = (Get-Process -Name EADesktop | Select-Object -First 1).Id }
& "$r\t45_focus.ps1" -TargetPid $TargetPid -W $W -H $H | Out-Null
Get-Content "$r\_focus.txt"
Start-Sleep -Milliseconds 900
& "$r\shot_desk.ps1" | Out-Null
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile("$r\shot_desk.png")
$crop = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $W, $H), (New-Object System.Drawing.Rectangle 40, 20, $W, $H), 'Pixel')
$sc = [math]::Min(1000 / $W, 1500 / $H)
$bw = [int]($W * $sc); $bh = [int]($H * $sc)
$big = New-Object System.Drawing.Bitmap $bw, $bh
$g2 = [System.Drawing.Graphics]::FromImage($big); $g2.InterpolationMode = 'HighQualityBicubic'
$g2.DrawImage($crop, 0, 0, $bw, $bh)
$big.Save("$r\_$($Tag)_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g2.Dispose(); $big.Dispose(); $g.Dispose(); $crop.Dispose(); $src.Dispose()
