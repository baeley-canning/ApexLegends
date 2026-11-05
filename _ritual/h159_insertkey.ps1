# h159_insertkey.ps1 - bring the game window forward and send VK_INSERT (extended key).
# INSERT is the documented ESP toggle in hooks.cpp:570 (WM_KEYDOWN && VK_INSERT).
param([int]$Pid = 0, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h159_key.txt')
Add-Type @'
using System; using System.Runtime.InteropServices;
public class KW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e);
}
'@
$log = @()
$p = if ($Pid) { Get-Process -Id $Pid -EA 0 } else { Get-Process r5apex_dx12, r5apex -EA 0 | Select-Object -First 1 }
if (-not $p) { 'NO GAME PROCESS' | Set-Content -LiteralPath $Out; exit 1 }
$h = $p.MainWindowHandle
$log += ('pid=' + $p.Id + ' hwnd=' + $h + ' title=' + $p.MainWindowTitle)
if ($h -ne 0) {
    [void][KW]::ShowWindow($h, 9)   # SW_RESTORE
    [void][KW]::BringWindowToTop($h)
    [void][KW]::SetForegroundWindow($h)
    $log += 'foreground raised'
}
Start-Sleep -Milliseconds 600
# VK_INSERT 0x2D, scancode 0x52, KEYEVENTF_EXTENDEDKEY 0x1
[KW]::keybd_event(0x2D, 0x52, 0x1, [IntPtr]::Zero)
Start-Sleep -Milliseconds 90
[KW]::keybd_event(0x2D, 0x52, 0x1 -bor 0x2, [IntPtr]::Zero)
$log += 'VK_INSERT sent'
$log | Set-Content -LiteralPath $Out -Encoding UTF8
Get-Content -LiteralPath $Out
