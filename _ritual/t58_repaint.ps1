# t58_repaint.ps1 - force a CEF repaint by minimising and restoring the window, then crop.
param([string]$Tag = 't58')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
Add-Type @'
using System; using System.Runtime.InteropServices;
public class RP {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  public struct RECT { public int L, T, R, B; }
}
'@
$p = (Get-Process -Name EADesktop | Select-Object -First 1).Id
$hit = New-Object System.Collections.ArrayList
$cb = [RP+P]{
  param($w, $l)
  $q = 0; [void][RP]::GetWindowThreadProcessId($w, [ref]$q)
  if ($q -eq $p -and [RP]::IsWindowVisible($w)) {
    $rc = New-Object RP+RECT; [void][RP]::GetWindowRect($w, [ref]$rc)
    if (($rc.R - $rc.L) -gt 200) { [void]$hit.Add($w) }
  }
  return $true
}
[void][RP]::EnumWindows($cb, [IntPtr]::Zero)
if (-not $hit.Count) { 'no window' | Set-Content -LiteralPath "$r\_$($Tag).txt"; exit 1 }
$h = [IntPtr]$hit[0]
[void][RP]::ShowWindow($h, 6)
Start-Sleep -Milliseconds 700
[void][RP]::ShowWindow($h, 9)
Start-Sleep -Milliseconds 1800

& "$r\t56_crop.ps1" -Tag $Tag
