# t50_signup.ps1 - open the create-account form and fill DOB 15 May 1998.
# Everything runs in ONE process: a capture or a new console in between steals foreground and
# the CEF page then ignores the keys (see _t42). Coordinates are for the 520x867 window at 40,20.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$pid2 = (Get-Process -Name EADesktop | Where-Object MainWindowTitle | Select-Object -First 1).Id
& "$r\t45_focus.ps1" -TargetPid $pid2 | Out-Null
& "$r\click.ps1" -X 298 -Y 763 | Out-Null
Start-Sleep -Seconds 3
$L = @()
foreach ($f in @(@{ n = 'month'; x = 178; y = 610; k = 'HOME,DOWN,DOWN,DOWN,DOWN,DOWN' },
                 @{ n = 'day';   x = 322; y = 610; k = '1,5' },
                 @{ n = 'year';  x = 444; y = 610; k = '1,9,9,8' })) {
  & "$r\click.ps1" -X $f.x -Y $f.y | Out-Null
  Start-Sleep -Milliseconds 300
  & "$r\sendkey.ps1" -Keys $f.k -Out "$r\_t50_$($f.n).txt" | Out-Null
  Start-Sleep -Milliseconds 200
  & "$r\sendkey.ps1" -Keys 'ENTER' -Out "$r\_t50_$($f.n)_e.txt" | Out-Null
  Start-Sleep -Milliseconds 600
  $L += "$($f.n) $($f.x),$($f.y) keys=$($f.k)+ENTER"
}
Start-Sleep -Milliseconds 600
& "$r\shot_win.ps1" -TargetPid $pid2 -Out "$r\_t50.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_t50.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_t50_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
$L -join "`r`n" | Set-Content -LiteralPath "$r\_t50.txt"
