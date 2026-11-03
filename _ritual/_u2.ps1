# _u2.ps1 - what is on top of the desktop right now, and is the cursor clipped?
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u2.txt'
"=== u2 $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }

Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class D2 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool GetClipCursor(out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Dump(){
    StringBuilder sb = new StringBuilder(); int n = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l){
      if(!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      StringBuilder c = new StringBuilder(128); GetClassName(h, c, 128);
      StringBuilder t = new StringBuilder(128); GetWindowText(h, t, 128);
      uint p = 0; GetWindowThreadProcessId(h, out p);
      long ex = (long)GetWindowLongPtr(h, -20);
      sb.AppendLine(string.Format("{0} pid={1} ex=0x{2:X} [{3},{4} {5}x{6}] {7} :: {8}",
        h, p, ex, r.L, r.T, r.R-r.L, r.B-r.T, c.ToString(), t.ToString()));
      return ++n < 25;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
W ("screen " + [D2]::GetSystemMetrics(0) + "x" + [D2]::GetSystemMetrics(1))
$cr = New-Object D2+RECT
if([D2]::GetClipCursor([ref]$cr)){ W ("clip [" + $cr.L + "," + $cr.T + " " + ($cr.R-$cr.L) + "x" + ($cr.B-$cr.T) + "]") } else { W 'clip none' }
foreach($xy in @(@(100,100), @(960,400), @(1158,938), @(600,1050))){
  $p = New-Object D2+POINT; $p.X = $xy[0]; $p.Y = $xy[1]
  $h = [D2]::WindowFromPoint($p)
  $sb = New-Object System.Text.StringBuilder 128; [void][D2]::GetClassName($h, $sb, 128)
  W ("hit $($xy[0]),$($xy[1]) -> $h [" + $sb.ToString() + "]")
}
W '--- top-level z-order (first 25 visible) ---'
[D2]::Dump().TrimEnd() -split "`r?`n" | ForEach-Object { W $_ }
Get-Content -LiteralPath $log
