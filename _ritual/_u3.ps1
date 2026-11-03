# _u3.ps1 - identify the full-screen render host that is eating clicks
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u3.txt'
"=== u3 $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class D3 {
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
foreach($h in 197936, 67524){
  $H = [IntPtr]$h
  if(-not [D3]::IsWindow($H)){ W "$h not a window"; continue }
  $r = New-Object D3+RECT; [void][D3]::GetWindowRect($H, [ref]$r)
  $sb = New-Object System.Text.StringBuilder 128; [void][D3]::GetClassName($H, $sb, 128)
  $p = 0; [void][D3]::GetWindowThreadProcessId($H, [ref]$p)
  $par = [D3]::GetParent($H); $root = [D3]::GetAncestor($H, 2)
  $proc = try { (Get-Process -Id $p -EA Stop).ProcessName } catch { '?' }
  W ("$h pid=$p($proc) vis=" + [D3]::IsWindowVisible($H) + " style=0x" + ([D3]::GetWindowLongPtr($H,-16).ToString('X')) + " ex=0x" + ([D3]::GetWindowLongPtr($H,-20).ToString('X')))
  W ("  class=" + $sb.ToString() + " rect=[" + $r.L + "," + $r.T + " " + ($r.R-$r.L) + "x" + ($r.B-$r.T) + "] parent=$par root=$root")
}
Get-Content -LiteralPath $log
