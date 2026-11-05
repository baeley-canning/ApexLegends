# click_hi: DPI-aware click.  WinForms makes the process DPI-aware so SetCursorPos
# takes true pixel coordinates (same reason as shot_hi).
param([int]$X, [int]$Y)
Add-Type -AssemblyName System.Windows.Forms
$null = New-Object System.Windows.Forms.Form
Add-Type @'
using System; using System.Runtime.InteropServices;
public class MH {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
}
'@
[void][MH]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 150
[MH]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[MH]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
"click $X,$Y"
