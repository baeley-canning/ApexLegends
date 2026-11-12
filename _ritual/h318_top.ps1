# h318_top.ps1 - restore + force a window topmost, then optional click (the EA app hides behind the
# elevated consoles, and a topmost call alone does not un-minimise it).
param([Parameter(Mandatory = $true)][string]$ProcName, [int]$X = -1, [int]$Y = -1)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class T {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
'@
$p = @(Get-Process $ProcName -EA 0 | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $p) { 'no window'; exit 1 }
[void][T]::ShowWindow($p.MainWindowHandle, 9)
Start-Sleep -Milliseconds 400
[void][T]::SetWindowPos($p.MainWindowHandle, [IntPtr](-1), 0, 0, 0, 0, 0x3)
Start-Sleep -Milliseconds 300
[void][T]::SetForegroundWindow($p.MainWindowHandle)
'focused ' + $ProcName
if ($X -ge 0 -and $Y -ge 0) {
    Start-Sleep -Milliseconds 400
    [void][T]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 250
    [T]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [T]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    'clicked ' + $X + ',' + $Y
}
