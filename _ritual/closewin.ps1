# closewin.ps1 - close a visible top-level window whose title contains the pattern (WM_CLOSE).
param([string]$Pattern = 'VirtualBox - Error')
Add-Type -AssemblyName System.Windows.Forms
$null = New-Object System.Windows.Forms.Form
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class CW {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public delegate bool EP(IntPtr h, IntPtr l);
  public static string Pat = "";
  public static int N = 0;
  public static bool Cb(IntPtr h, IntPtr l) {
    if (!IsWindowVisible(h)) return true;
    var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
    if (sb.ToString().Contains(Pat)) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); N++; }
    return true;
  }
}
'@
[CW]::Pat = $Pattern
[void][CW]::EnumWindows([CW+EP]{ param($h, $l) [CW]::Cb($h, $l) }, [IntPtr]::Zero)
"closed $([CW]::N) window(s) matching '$Pattern'"