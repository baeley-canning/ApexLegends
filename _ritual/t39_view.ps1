# t39_view.ps1 - capture the EA window and write a half-scale jpg for reading.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& "$r\shot_win.ps1" -TargetPid 24504 -Out "$r\_t39.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_t39.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_t39_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
