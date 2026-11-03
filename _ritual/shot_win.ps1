# capture one top-level window by pid (PrintWindow, works even if covered)
param([int]$TargetPid = 0, [string]$Out = '', [string]$Title = '')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  public struct RECT { public int L, T, R, B; }
}
'@
$found = New-Object System.Collections.ArrayList
$cb = [W+EnumProc]{
  param($h, $l)
  $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
  $hit = if($Title) { $false } else { $p -eq $TargetPid }
  if($Title){
    $n2 = [W]::GetWindowTextLength($h); $sb2 = New-Object System.Text.StringBuilder ($n2 + 2)
    [void][W]::GetWindowText($h, $sb2, $sb2.Capacity)
    if($sb2.ToString() -match $Title){ $hit = $true }
  }
  if($hit -and [W]::IsWindowVisible($h)){
    $n = [W]::GetWindowTextLength($h); $sb = New-Object System.Text.StringBuilder ($n + 2)
    [void][W]::GetWindowText($h, $sb, $sb.Capacity)
    $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
    if(($r.R - $r.L) -gt 200){ [void]$found.Add([pscustomobject]@{h=$h; t=$sb.ToString(); w=$r.R-$r.L; ht=$r.B-$r.T}) }
  }
  return $true
}
[void][W]::EnumWindows($cb, [IntPtr]::Zero)
if(-not $found.Count){ 'no visible window for pid ' + $TargetPid; exit }
$w = $found | Sort-Object { $_.w * $_.ht } -Descending | Select-Object -First 1
'window: "' + $w.t + '" ' + $w.w + 'x' + $w.ht
# restore + raise, then grab the on-screen rect (PrintWindow is black for Chromium windows)
Add-Type @'
using System; using System.Runtime.InteropServices;
public class S {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
'@
[void][S]::ShowWindow($w.h, 9)
[void][S]::SetWindowPos($w.h, [IntPtr](-1), 40, 20, $w.w, $w.ht, 0x40)
[void][S]::SetForegroundWindow($w.h)
Start-Sleep -Milliseconds 700
$r = New-Object W+RECT; [void][W]::GetWindowRect($w.h, [ref]$r)
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
'captured -> ' + $Out
