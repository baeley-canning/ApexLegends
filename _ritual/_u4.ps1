# _u4.ps1 - is a consent prompt up, is VS Code hung, are there modal dialogs?
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u4.txt'
"=== u4 $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class D4 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr pr, EP p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint t);
  [DllImport("user32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool GetUserObjectInformation(IntPtr h, int i, StringBuilder b, int n, out int need);
  public static string DeskName(){
    StringBuilder b = new StringBuilder(256); int n;
    GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()), 2, b, 512, out n);
    return b.ToString();
  }
  public static string Scan(){
    StringBuilder sb = new StringBuilder();
    EnumWindows(delegate(IntPtr h, IntPtr l){
      StringBuilder c = new StringBuilder(128); GetClassName(h, c, 128);
      string cl = c.ToString();
      if(cl == "#32770" || cl.Contains("Credential") || cl.Contains("Flighted") || cl.Contains("TaskDialog")){
        StringBuilder t = new StringBuilder(160); GetWindowText(h, t, 160);
        uint p = 0; GetWindowThreadProcessId(h, out p);
        sb.AppendLine(string.Format("dlg {0} pid={1} vis={2} en={3} [{4}] :: {5}", h, p, IsWindowVisible(h), IsWindowEnabled(h), cl, t.ToString()));
      }
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
W ("desktop        = " + [D4]::DeskName())
W ("foreground     = " + [D4]::GetForegroundWindow())
$c = @(Get-Process consent -EA SilentlyContinue)
W ("consent.exe    = " + $c.Count)
foreach($p in $c){ W ("  consent pid=" + $p.Id + " responding=" + $p.Responding) }
foreach($p in @(Get-Process Code -EA SilentlyContinue)){
  W ("  Code pid=" + $p.Id + " responding=" + $p.Responding + " mainwnd=" + $p.MainWindowHandle)
}
$d = [D4]::Scan().TrimEnd()
if($d){ W '--- dialogs ---'; $d -split "`r?`n" | ForEach-Object { W $_ } } else { W 'no #32770-style dialogs' }
W '--- EA child tree ---'
$ea = [IntPtr]67524
[void][D4]::EnumChildWindows($ea, [D4+EP]{ param($h,$l) $sb=New-Object System.Text.StringBuilder 128; [void][D4]::GetClassName($h,$sb,128); $script:out += ("  $h " + $sb.ToString() + " vis=" + [D4]::IsWindowVisible($h) + " en=" + [D4]::IsWindowEnabled($h)); $true }, [IntPtr]::Zero)
if($script:out){ $script:out | ForEach-Object { W $_ } } else { W '  (no children)' }
Get-Content -LiteralPath $log
