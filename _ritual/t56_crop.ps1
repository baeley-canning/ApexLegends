# t56_crop.ps1 - capture the EA window by cropping the desktop instead of the window surface.
# CopyFromScreen on the window goes black once it is active (DirectComposition); desktop pixels
# are always composed, so the crop is the only trustworthy picture. Window is fixed at 40,20 520x867.
param([string]$Tag = 't56')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& "$r\shot_desk.ps1" | Out-Null
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile("$r\shot_desk.png")
$crop = New-Object System.Drawing.Bitmap 520, 867
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 520, 867), (New-Object System.Drawing.Rectangle 40, 20, 520, 867), 'Pixel')
$big = New-Object System.Drawing.Bitmap 700, 1166
$g2 = [System.Drawing.Graphics]::FromImage($big); $g2.InterpolationMode = 'HighQualityBicubic'
$g2.DrawImage($crop, 0, 0, 700, 1166)
$big.Save("$r\_$($Tag)_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g2.Dispose(); $big.Dispose(); $g.Dispose(); $crop.Dispose(); $src.Dispose()
