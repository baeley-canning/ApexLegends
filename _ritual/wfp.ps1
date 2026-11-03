param([int]$X = 963, [int]$Y = 579, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_wfp.txt')
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  public struct POINT { public int X; public int Y; }
}
'@
$p = New-Object W+POINT; $p.X = $X; $p.Y = $Y
$h = [W]::WindowFromPoint($p)
$root = [W]::GetAncestor($h, 2)
$sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($h, $sb, 256)
$cn = New-Object System.Text.StringBuilder 256; [void][W]::GetClassName($h, $cn, 256)
$sb2 = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($root, $sb2, 256)
$pid1 = [uint32]0; [void][W]::GetWindowThreadProcessId($root, [ref]$pid1)
$proc = (Get-Process -Id $pid1 -EA SilentlyContinue).ProcessName
"hit=$h root=$root title='$($sb.ToString())' class='$($cn.ToString())' rootTitle='$($sb2.ToString())' rootPid=$pid1 proc=$proc fg=$([W]::GetForegroundWindow())" | Set-Content -LiteralPath $Out
