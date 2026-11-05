param([string]$Title = 'Win11-Test2', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h353.txt')
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class C {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public struct RECT { public int L, T, R, B; }
}
'@
$t = [IntPtr]::Zero
$cb = [C+EnumProc]{
    param($h, $p)
    if ([C]::IsWindowVisible($h)) {
        $sb = New-Object System.Text.StringBuilder 512
        [void][C]::GetWindowText($h, $sb, 512)
        if ($sb.Length -gt 0 -and $sb.ToString() -match $Title) { $script:t = $h; return $false }
    }
    return $true
}
[void][C]::EnumWindows($cb, [IntPtr]::Zero)
if ($t -eq [IntPtr]::Zero) { 'NOTFOUND' | Set-Content -LiteralPath $Out; exit 1 }
[void][C]::ShowWindow($t, 9)
[void][C]::BringWindowToTop($t)
[void][C]::SetForegroundWindow($t)
Start-Sleep -Milliseconds 500
$r = New-Object C+RECT
[void][C]::GetWindowRect($t, [ref]$r)
$x = [int](($r.L + $r.R) / 2); $y = [int](($r.T + $r.B) / 2)
[void][C]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 250
[C]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[C]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
"clicked $x,$y hwnd=$t rect=$($r.L),$($r.T),$($r.R),$($r.B)" | Set-Content -LiteralPath $Out
