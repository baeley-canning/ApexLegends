param([string]$Title, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_raise.txt')
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class R {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern IntPtr SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  public struct POINT { public int X; public int Y; }
}
'@
$target = [IntPtr]::Zero
$cb = [R+EnumProc]{
  param($h, $p)
  if([R]::IsWindowVisible($h)){
    $n = [R]::GetWindowText($h, (New-Object System.Text.StringBuilder 512), 512)
    $sb = New-Object System.Text.StringBuilder 512
    [void][R]::GetWindowText($h, $sb, 512)
    if($sb.Length -gt 0 -and $sb.ToString() -match $Title){ $script:target = $h; return $false }
  }
  return $true
}
[void][R]::EnumWindows($cb, [IntPtr]::Zero)
if($target -eq [IntPtr]::Zero){ 'NOTFOUND' | Set-Content -LiteralPath $Out; exit 1 }
[void][R]::ShowWindow($target, 9)          # SW_RESTORE
[void][R]::BringWindowToTop($target)
$curT = [R]::GetCurrentThreadId()
$fgT  = [R]::GetWindowThreadProcessId([R]::GetForegroundWindow(), [ref]([uint32]0))
[void][R]::AttachThreadInput($curT, $fgT, $true)
[void][R]::SetForegroundWindow($target)
[void][R]::SetFocus($target)
[void][R]::AttachThreadInput($curT, $fgT, $false)
Start-Sleep -Milliseconds 400
$fg = [R]::GetForegroundWindow()
$sb2 = New-Object System.Text.StringBuilder 512
[void][R]::GetWindowText($fg, $sb2, 512)
"target=$target  fg=$($fg)  fgtitle=$($sb2.ToString())" | Set-Content -LiteralPath $Out
