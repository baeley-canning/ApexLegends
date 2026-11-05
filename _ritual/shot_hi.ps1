# shot_hi: DPI-aware full-screen capture.  WinForms forces the process DPI-aware,
# so SystemInformation.VirtualScreen and CopyFromScreen see true pixels (1920x1080),
# not the 1024x768 virtualised rectangle an unaware process gets.
param([string]$Out)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$null = New-Object System.Windows.Forms.Form    # forces DPI awareness
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$($b.Width)x$($b.Height)" | Set-Content ($Out + '.size.txt')
$bmp.Dispose()
