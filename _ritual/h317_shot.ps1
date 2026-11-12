# h317_shot.ps1 - host screen capture (the EA app / Apex state is what tells us why the game is not
# starting). Read-only. New file per call.
param([string]$Name = 'h317_screen')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$w = [int]($b.Width * 0.40); $h = [int]($b.Height * 0.40)
$sm = New-Object System.Drawing.Bitmap $w, $h
$g2 = [System.Drawing.Graphics]::FromImage($sm)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($bmp, 0, 0, $w, $h)
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ps = New-Object System.Drawing.Imaging.EncoderParameters 1
$ps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 42
$p = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ($Name + '.jpg')
$sm.Save($p, $enc, $ps)
$g.Dispose(); $g2.Dispose(); $bmp.Dispose(); $sm.Dispose()
'OK ' + $p + ' ' + (Get-Item $p).Length



