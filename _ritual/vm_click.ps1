# vm_click.ps1 - click inside the VirtualBox VM window at GUEST pixel coordinates.
# Needed because this safe-mode session's Start flyout swallows all letters (search box dead), so
# neither winr nor typing reaches a shell. Path in: click the pinned PowerShell taskbar icon.
# WinForms() first = DPI aware, same reason as click_hi.ps1. Guest is 1024x768; client rect scale
# is computed from the live window, so it survives a resize.
param([int]$X, [int]$Y, [switch]$Right, [string]$Title = 'Win11-Test2')
Add-Type -AssemblyName System.Windows.Forms
$null = New-Object System.Windows.Forms.Form
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class VW {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L, T, R, B; }
  public struct POINT { public int X, Y; }
  public static IntPtr Find(string pat) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
      if (sb.ToString().Contains(pat)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
$h = [VW]::Find($Title)
if ($h -eq [IntPtr]::Zero) { "no window for '$Title'"; exit 1 }
[void][VW]::ShowWindow($h, 9)
[void][VW]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400
$r = New-Object VW+RECT
if (-not [VW]::GetClientRect($h, [ref]$r)) { 'GetClientRect failed'; exit 1 }
$p = New-Object VW+POINT
$p.X = 0; $p.Y = 0
[void][VW]::ClientToScreen($h, [ref]$p)
$w = $r.R - $r.L; $hh = $r.B - $r.T
if ($w -lt 200 -or $hh -lt 200) { "client too small: ${w}x${hh}"; exit 1 }
# framebuffer is 1024x768 in a possibly-taller/wider client: scale to fit, centre the band offset
$s = [Math]::Min($w / 1024.0, $hh / 768.0)
$ox = ($w - 1024 * $s) / 2; $oy = ($hh - 768 * $s) / 2
$hx = [int]($p.X + $ox + $X * $s); $hy = [int]($p.Y + $oy + $Y * $s)
[void][VW]::mouse_event(0x8000, 0, 0, 0, [IntPtr]::Zero)   # move to host point first
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($hx, $hy)
Start-Sleep -Milliseconds 250
$dn = 0x0002; $up = 0x0004
if ($Right) { $dn = 0x0008; $up = 0x0010 }
[VW]::mouse_event($dn, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[VW]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
"click guest $X,$Y -> host $hx,$hy (client ${w}x${hh} at $($p.X),$($p.Y))"
