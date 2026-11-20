# t53_post.ps1 - click by PostMessage straight into the CEF window, bypassing z-order.
# The EA app has a Qt frame AND a Chrome_WidgetWin_0 at the identical rect; a system-level click
# lands on whichever is on top and the page never sees it. Client coords are screen minus the
# window origin (40,20) - the window draws its own title bar inside the client area.
param([int]$ScreenX = 298, [int]$ScreenY = 763, [string]$Tag = 't53')
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class PW {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct RECT { public int L, T, R, B; }
}
'@
$p = (Get-Process -Name EADesktop | Where-Object MainWindowTitle | Select-Object -First 1).Id
$hit = New-Object System.Collections.ArrayList
$cb = [PW+P]{
  param($w, $l)
  $q = 0; [void][PW]::GetWindowThreadProcessId($w, [ref]$q)
  if ($q -eq $p -and [PW]::IsWindowVisible($w)) {
    $cn = New-Object System.Text.StringBuilder 128; [void][PW]::GetClassName($w, $cn, 128)
    $rc = New-Object PW+RECT; [void][PW]::GetWindowRect($w, [ref]$rc)
    if ($cn.ToString() -eq 'Chrome_WidgetWin_0' -and ($rc.R - $rc.L) -gt 200) {
      [void]$hit.Add([pscustomobject]@{ h = $w; ox = $rc.L; oy = $rc.T })
    }
  }
  return $true
}
[void][PW]::EnumWindows($cb, [IntPtr]::Zero)
if (-not $hit.Count) { 'no chrome window' | Set-Content -LiteralPath "$r\_$Tag.txt"; exit 1 }
$t = $hit[0]
$cx = $ScreenX - $t.ox; $cy = $ScreenY - $t.oy
[void][PW]::SetForegroundWindow([IntPtr]$t.h)
$lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
[void][PW]::PostMessage([IntPtr]$t.h, 0x0200, [IntPtr]0, $lp)   # WM_MOUSEMOVE
Start-Sleep -Milliseconds 120
[void][PW]::PostMessage([IntPtr]$t.h, 0x0201, [IntPtr]1, $lp)   # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 90
[void][PW]::PostMessage([IntPtr]$t.h, 0x0202, [IntPtr]0, $lp)   # WM_LBUTTONUP
Start-Sleep -Milliseconds 1200
& "$r\shot_win.ps1" -TargetPid $p -Out "$r\_$Tag.png" | Out-Null
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile("$r\_$Tag.png")
$b = New-Object System.Drawing.Bitmap 700, 1166
$g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($i, 0, 0, 700, 1166)
$b.Save("$r\_$($Tag)_small.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $b.Dispose(); $i.Dispose()
"posted $cx,$cy to hwnd $($t.h) (screen $ScreenX,$ScreenY)" | Set-Content -LiteralPath "$r\_$Tag.txt"
