# wins.ps1 - list visible top-level windows that look like VirtualBox + the running VMs.
Add-Type -AssemblyName System.Windows.Forms
$null = New-Object System.Windows.Forms.Form
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class EW {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R rr);
  public delegate bool EP(IntPtr h, IntPtr l);
  public struct R { public int L, T, Rt, B; }
  public static System.Collections.ArrayList Hits = new System.Collections.ArrayList();
  public static bool Cb(IntPtr h, IntPtr l) {
    if (!IsWindowVisible(h)) return true;
    var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
    string t = sb.ToString();
    if (t.Contains("VirtualBox") || t.Contains("Win11") || t.Contains("VBox")) {
      R r; GetWindowRect(h, out r);
      Hits.Add(string.Format("{0} :: [{1}] :: {2}x{3} at {4},{5}", h, t, r.Rt - r.L, r.B - r.T, r.L, r.T));
    }
    return true;
  }
}
'@
[void][EW]::EnumWindows([EW+EP]{ param($h, $l) [EW]::Cb($h, $l) }, [IntPtr]::Zero)
foreach ($x in [EW]::Hits) { Write-Output $x }
Write-Output '--- runningvms ---'
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' list runningvms