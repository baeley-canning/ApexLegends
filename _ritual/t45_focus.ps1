# t45_focus.ps1 - force the EA window to the foreground and PROVE it, before any click.
# WScript.AppActivate is unreliable here: it reported success while the foreground stayed on
# VS Code and every click landed in the editor. This uses the ALT-key + SetForegroundWindow
# trick, then reads GetForegroundWindow back and fails loudly if it is a different window.
param([int]$TargetPid = 24504, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_focus.txt', [int]$W = 520, [int]$H = 867)

Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class FZ {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  public struct RECT { public int L, T, R, B; }
}
'@
$hit = New-Object System.Collections.ArrayList
$cb = [FZ+EnumProc]{
  param($w, $l)
  $p = 0; [void][FZ]::GetWindowThreadProcessId($w, [ref]$p)
  if ($p -eq $TargetPid) { [void]$hit.Add($w) }
  return $true
}
[void][FZ]::EnumWindows($cb, [IntPtr]::Zero)
if (-not $hit.Count) { "FAIL: no window for pid $TargetPid" | Set-Content -LiteralPath $Out; Write-Host 'FAIL no window'; exit 1 }
# 19/11: window was found minimized twice (frame iconic at -32000, content window hidden).
# Restore everything the pid owns, then pick the largest *visible* window.
foreach ($w in $hit) { [void][FZ]::ShowWindow($w, 9) }
Start-Sleep -Milliseconds 700
$vis = New-Object System.Collections.ArrayList
$cb2 = [FZ+EnumProc]{
  param($w, $l)
  $p = 0; [void][FZ]::GetWindowThreadProcessId($w, [ref]$p)
  if ($p -eq $TargetPid -and [FZ]::IsWindowVisible($w)) {
    $q = New-Object FZ+RECT; [void][FZ]::GetWindowRect($w, [ref]$q)
    if (($q.R - $q.L) -gt 200) { [void]$vis.Add([pscustomobject]@{ h = $w; a = ($q.R - $q.L) * ($q.B - $q.T) }) }
  }
  return $true
}
[void][FZ]::EnumWindows($cb2, [IntPtr]::Zero)
if (-not $vis.Count) { "FAIL: restored but no visible content window" | Set-Content -LiteralPath $Out; Write-Host 'FAIL not visible'; exit 1 }
$h = [IntPtr](($vis | Sort-Object a -Descending | Select-Object -First 1).h)
# fixed size keeps the capture at 520x867, so the screen coordinates measured earlier stay valid
[void][FZ]::SetWindowPos($h, [IntPtr](-1), 40, 20, $W, $H, 0x40)

[FZ]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
[FZ]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 120
[void][FZ]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400
$fg = [FZ]::GetForegroundWindow()
$ok = ($fg -eq $h)
"target=$h foreground=$fg ok=$ok" | Set-Content -LiteralPath $Out
if ($ok) { Write-Host 'focus ok' } else { Write-Host "focus FAIL fg=$fg" }
