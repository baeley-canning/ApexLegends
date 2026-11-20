# t38_dob.ps1 - fill Month/Day/Year 6 / 15 / 1998 on the EA create-account form.
# Window is pinned at 40,20 by shot_win; field centres in screen px were measured off _t37_dob.png.
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$L = @()
& "$r\sendkey.ps1" -Keys 'ESC' -Out "$r\_t38_esc.txt" | Out-Null
Start-Sleep -Milliseconds 500
$fields = @(
  @{ n = 'month'; x = 178; y = 610; k = '6' },
  @{ n = 'day';   x = 322; y = 610; k = '1,5' },
  @{ n = 'year';  x = 444; y = 610; k = '1,9,9,8' }
)
foreach ($f in $fields) {
  & "$r\click.ps1" -X $f.x -Y $f.y | Out-Null
  Start-Sleep -Milliseconds 900
  $o = "$r\_t38_$($f.n).txt"
  & "$r\sendkey.ps1" -Keys $f.k -Out $o | Out-Null
  Start-Sleep -Milliseconds 500
  & "$r\sendkey.ps1" -Keys 'ENTER' -Out "$r\_t38_$($f.n)_ent.txt" | Out-Null
  Start-Sleep -Milliseconds 700
  $L += "$($f.n): clicked $($f.x),$($f.y) keys $($f.k) then ENTER"
}
& "$r\shot_win.ps1" -TargetPid 24504 -Out "$r\_t38_after.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_t38_after.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_t38_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
$L -join "`r`n" | Out-File -LiteralPath "$r\_t38_dob.txt" -Encoding utf8
