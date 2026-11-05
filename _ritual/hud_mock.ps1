param([int]$Hp = 100, [int]$Shield = 100, [int]$Down = 0, [string]$Out = 'C:\p37vm\ocr\hud.png',
      [int]$W = 900, [int]$H = 230)
# hud_mock.ps1 -- draw one fake health HUD frame for the p98 ingest bench.
# Not a screenshot of Apex: a stand-in with the same shape (big light digits, dark ground) so the
# OCR -> consumer path is exercised without a live game or kernel reads.
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(18, 22, 26))
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$f = New-Object System.Drawing.Font 'Segoe UI', 64, ([System.Drawing.FontStyle]::Bold)
$g.DrawString(('HP {0}' -f $Hp), $f, [System.Drawing.Brushes]::White, 24, 20)
$g.DrawString(('SHIELD {0}' -f $Shield), $f, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150,210,255))), 24, 120)
if ($Down -eq 1) {
    $g.DrawString('DOWN', $f, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,190,90))), 620, 20)
}
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
'saved ' + $Out
