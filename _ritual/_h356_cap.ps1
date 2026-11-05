param([string]$Title = 'Win11-Test2', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_cap.png')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int L, T, R, B; }
}
'@
$t = [IntPtr]::Zero
$cb = [W+EnumProc]{
    param($h, $p)
    if ([W]::IsWindowVisible($h)) {
        $sb = New-Object System.Text.StringBuilder 512
        [void][W]::GetWindowText($h, $sb, 512)
        if ($sb.Length -gt 0 -and $sb.ToString() -match $Title) { $script:t = $h; return $false }
    }
    return $true
}
[void][W]::EnumWindows($cb, [IntPtr]::Zero)
if ($t -eq [IntPtr]::Zero) { 'NOTFOUND' | Set-Content -LiteralPath ([IO.Path]::ChangeExtension($Out, '.txt')); exit 1 }
$r = New-Object W+RECT
[void][W]::GetWindowRect($t, [ref]$r)
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"cap $w x $h"
