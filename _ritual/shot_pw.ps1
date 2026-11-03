param([string]$Title = '^EA$', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\pw.png')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class P {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr hrgn, uint f);
  public struct RECT { public int L, T, R, B; }
}
'@
$t = [IntPtr]::Zero
$cb = [P+EnumProc]{
  param($h, $l)
  if ([P]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 400
    [void][P]::GetWindowText($h, $sb, 400)
    if ($sb.ToString() -match $Title) { $script:t = $h; return $false }
  }
  return $true
}
[void][P]::EnumWindows($cb, [IntPtr]::Zero)
if ($t -eq [IntPtr]::Zero) { 'NOTFOUND'; exit 1 }
[void][P]::RedrawWindow($t, [IntPtr]::Zero, [IntPtr]::Zero, 0x01 -bor 0x04 -bor 0x80)
Start-Sleep -Milliseconds 500
$r = New-Object P+RECT; [void][P]::GetWindowRect($t, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [P]::PrintWindow($t, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
'pw ok=' + $ok + ' ' + $w + 'x' + $h2
