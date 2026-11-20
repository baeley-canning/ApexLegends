# t49_look.ps1 - focus (verified), size, capture, and shrink for reading. One pid argument.
param([int]$TargetPid = 0, [string]$Tag = 't49')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
if (-not $TargetPid) { $TargetPid = (Get-Process -Name EADesktop | Where-Object MainWindowTitle | Select-Object -First 1).Id }
& "$r\t45_focus.ps1" -TargetPid $TargetPid | Out-Null
$f = Get-Content "$r\_focus.txt"
Start-Sleep -Milliseconds 900
& "$r\shot_win.ps1" -TargetPid $TargetPid -Out "$r\_$Tag.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_$Tag.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_$($Tag)_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
"pid=$TargetPid $f size=$($i.Width)" | Set-Content -LiteralPath "$r\_$($Tag).txt"
