# errtext.ps1 - dump the text of controls in the VirtualBox error dialog.
Add-Type -AssemblyName System.Windows.Forms
$null = New-Object System.Windows.Forms.Form
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class ET {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EP p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public delegate bool EP(IntPtr h, IntPtr l);
  public static IntPtr Found = IntPtr.Zero;
  public static bool Top(IntPtr h, IntPtr l) {
    var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
    if (sb.ToString().Contains("VirtualBox - Error")) { Found = h; return false; }
    return true;
  }
  public static System.Collections.ArrayList Txt = new System.Collections.ArrayList();
  public static bool Kid(IntPtr h, IntPtr l) {
    var sb = new StringBuilder(2048); GetWindowText(h, sb, 2048);
    var cn = new StringBuilder(128); GetClassName(h, cn, 128);
    if (sb.Length > 0) Txt.Add("[" + cn.ToString() + "] " + sb.ToString());
    return true;
  }
}
'@
[void][ET]::EnumWindows([ET+EP]{ param($h, $l) [ET]::Top($h, $l) }, [IntPtr]::Zero)
if ([ET]::Found -eq [IntPtr]::Zero) { 'no error dialog'; exit }
[void][ET]::EnumChildWindows([ET]::Found, [ET+EP]{ param($h, $l) [ET]::Kid($h, $l) }, [IntPtr]::Zero)
foreach ($t in [ET]::Txt) { Write-Output $t }