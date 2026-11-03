param([int]$X = 963, [int]$Y = 578, [string]$Title = '^Apex', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_pm.txt')
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class P {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
}
'@
$t = [IntPtr]::Zero
$cb = [P+EnumProc]{ param($h,$p) $sb = New-Object System.Text.StringBuilder 256; [void][P]::GetWindowText($h,$sb,256); if($sb.ToString() -match $Title){ $script:t = $h; return $false }; return $true }
[void][P]::EnumWindows($cb, [IntPtr]::Zero)
if($t -eq [IntPtr]::Zero){ 'NOTFOUND' | Set-Content -LiteralPath $Out; exit 1 }
$lp = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
[void][P]::PostMessage($t, 0x0200, [IntPtr]::Zero, $lp)         # WM_MOUSEMOVE
Start-Sleep -Milliseconds 120
[void][P]::PostMessage($t, 0x0201, [IntPtr]1, $lp)               # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 90
[void][P]::PostMessage($t, 0x0202, [IntPtr]0, $lp)               # WM_LBUTTONUP
"posted lbuttondown/up to $t at $X,$Y" | Set-Content -LiteralPath $Out
