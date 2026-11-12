# h317_click.ps1 - one logical left click at absolute screen coords (harness has no click tool on the
# host). Read-only w.r.t. state: it only moves the pointer, the UI decides what happens.
param([Parameter(Mandatory = $true)][int]$X, [Parameter(Mandatory = $true)][int]$Y)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
'@
[void][M]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 250
[M]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[M]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
'clicked ' + $X + ',' + $Y
