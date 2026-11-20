# t51_click.ps1 - one click on CREATE ACCOUNT with an immediate capture, to see the reaction
# without any other step in between. Prints hover/after states.
param([int]$X = 298, [int]$Y = 763, [string]$Tag = 't51')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$p = (Get-Process -Name EADesktop | Where-Object MainWindowTitle | Select-Object -First 1).Id
& "$r\t45_focus.ps1" -TargetPid $p | Out-Null
Add-Type @'
using System; using System.Runtime.InteropServices;
public class MC {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
}
'@
[void][MC]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 300
[MC]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[MC]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
& "$r\shot_win.ps1" -TargetPid $p -Out "$r\_$Tag.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_$Tag.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_$($Tag)_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
"clicked $X,$Y" | Set-Content -LiteralPath "$r\_$Tag.txt"
