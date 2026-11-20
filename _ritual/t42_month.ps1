# t42_month.ps1 - set the Month select to June. Click and keys must happen in the SAME process:
# a capture in between (shot_win calls SetForegroundWindow) drops the DOM focus, after which the
# page ignores keys. HOME pins the popup highlight to January, five DOWNs land on June.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& "$r\click.ps1" -X 178 -Y 610 | Out-Null
Start-Sleep -Milliseconds 250
& "$r\sendkey.ps1" -Keys 'HOME,DOWN,DOWN,DOWN,DOWN,DOWN,ENTER' -Out "$r\_t42_keys.txt" | Out-Null
Start-Sleep -Milliseconds 600
& "$r\shot_win.ps1" -TargetPid 24504 -Out "$r\_t42.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_t42.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_t42_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
