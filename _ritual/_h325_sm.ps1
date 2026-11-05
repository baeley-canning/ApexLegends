param([string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_sm.png')
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$tmp = [IO.Path]::ChangeExtension($Out, '.full.png')
& $vb controlvm 'Win11-Test2' screenshotpng $tmp | Out-Null
Add-Type -AssemblyName System.Drawing
Start-Sleep -Milliseconds 200
$src = [System.Drawing.Image]::FromFile($tmp)
$dst = New-Object System.Drawing.Bitmap -ArgumentList 480, 360
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($src, 0, 0, 480, 360)
$dst.Save($Out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $dst.Dispose(); $src.Dispose()
Remove-Item -LiteralPath $tmp -Force -EA 0
'ok ' + (Get-Item $Out).Length
