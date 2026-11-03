param([int]$X, [int]$Y, [int]$Steps = 14, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_slow.txt')
Add-Type @'
using System; using System.Runtime.InteropServices;
public class MS {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  public struct POINT { public int X; public int Y; }
}
'@
$p = New-Object MS+POINT
[void][MS]::GetCursorPos([ref]$p)
$sx = $p.X; $sy = $p.Y
for($i = 1; $i -le $Steps; $i++){
  $nx = [int]($sx + ($X - $sx) * $i / $Steps)
  $ny = [int]($sy + ($Y - $sy) * $i / $Steps)
  [void][MS]::SetCursorPos($nx, $ny)
  Start-Sleep -Milliseconds 25
}
Start-Sleep -Milliseconds 150
[MS]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[MS]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
"slow-click from $sx,$sy to $X,$Y in $Steps steps" | Set-Content -LiteralPath $Out
