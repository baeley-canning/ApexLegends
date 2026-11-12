# h318_focus.ps1 - raise a window by process name (EA app kept opening behind whatever is focused).
param([Parameter(Mandatory = $true)][string]$ProcName)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class F {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
'@
$p = @(Get-Process $ProcName -EA 0 | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $p) { 'no window for ' + $ProcName; exit 1 }
[void][F]::ShowWindow($p.MainWindowHandle, 9)
Start-Sleep -Milliseconds 300
[void][F]::SetForegroundWindow($p.MainWindowHandle)
'focused ' + $ProcName + ' pid=' + $p.Id
