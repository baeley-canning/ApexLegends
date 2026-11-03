param([string]$Out, [double]$Scale = 1, [int]$Cx = 0, [int]$Cy = 0, [int]$Cw = 0, [int]$Ch = 0)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
try {
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $src = $bmp
  if ($Cw -gt 0 -and $Ch -gt 0) {
    $c = New-Object System.Drawing.Bitmap $Cw, $Ch
    $gc = [System.Drawing.Graphics]::FromImage($c)
    $gc.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $Cw, $Ch), (New-Object System.Drawing.Rectangle $Cx, $Cy, $Cw, $Ch), 'Pixel')
    $gc.Dispose()
    $src = $c
  }
  if ($Scale -lt 1) {
    $bmp = New-Object System.Drawing.Bitmap ([int]($src.Width * $Scale)), ([int]($src.Height * $Scale))
    $g2 = [System.Drawing.Graphics]::FromImage($bmp)
    $g2.InterpolationMode = 'HighQualityBicubic'
    $g2.DrawImage($src, 0, 0, $bmp.Width, $bmp.Height)
    $g2.Dispose()
  } else {
    $bmp = $src
  }
  if ($Out -match '\.jpe?g$') {
    $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $p = New-Object System.Drawing.Imaging.EncoderParameters 1
    $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, 45L)
    $bmp.Save($Out, $enc, $p)
  } else { $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png) }
  $bmp.Dispose()
  'ok ' + $b.Width + 'x' + $b.Height
} catch {
  'FAIL ' + $_.Exception.Message
}

