# t55_acquire.ps1 - click the EA caption bar (which forces a real activation), then TAB, then
# capture. Used to find out whether the window receives input at all.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
& "$r\click.ps1" -X 300 -Y 30 | Out-Null
Start-Sleep -Milliseconds 600
& "$r\sendkey.ps1" -Keys 'TAB,TAB' -Out "$r\_t55_keys.txt" | Out-Null
Start-Sleep -Milliseconds 700
$p = (Get-Process -Name EADesktop | Where-Object MainWindowTitle | Select-Object -First 1).Id
& "$r\shot_win.ps1" -TargetPid $p -Out "$r\_t55.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_t55.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_t55_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
