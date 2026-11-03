# ea_post - drive EA's CEF form with posted window messages (WM_LBUTTON* + WM_CHAR) straight to the
# render widget. Injected SendInput never lands on this CEF surface, posted messages do.
# Coordinates are CLIENT-relative to the EA window (fields measured on a 520x867 render).
param([string]$Text = '', [int]$X = 252, [int]$Y = 426, [switch]$Enter)
$rit = $PSScriptRoot
$o   = Join-Path $rit 'ea_post.txt'
function W($t){ $t | Add-Content -LiteralPath $o; $t }
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class PM {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EP e, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  public static IntPtr Find(IntPtr root, string cls){
    IntPtr hit = IntPtr.Zero;
    EnumChildWindows(root, delegate(IntPtr h, IntPtr l){
      StringBuilder sb = new StringBuilder(200); GetClassName(h, sb, 200);
      if(sb.ToString() == cls){ hit = h; return false; }
      return true;
    }, IntPtr.Zero);
    return hit;
  }
  public static void Click(IntPtr h, int absX, int absY){
    POINT p = new POINT(); p.X = 0; p.Y = 0;
    ClientToScreen(h, ref p);                       // client origin on screen
    int x = absX - p.X, y = absY - p.Y;
    IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
    PostMessage(h, 0x0200, IntPtr.Zero, lp);            // WM_MOUSEMOVE
    System.Threading.Thread.Sleep(80);
    PostMessage(h, 0x0201, (IntPtr)1, lp);              // WM_LBUTTONDOWN
    System.Threading.Thread.Sleep(60);
    PostMessage(h, 0x0202, IntPtr.Zero, lp);            // WM_LBUTTONUP
    System.Threading.Thread.Sleep(250);
  }
}
'@
$ea = @(Get-Process EADesktop -EA SilentlyContinue)
if(-not $ea.Count){ 'EA not running'; exit 1 }
$pids = @($ea | ForEach-Object { $_.Id })
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class TW {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  public static IntPtr Find(int[] pids){
    IntPtr hit = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l){
      uint p = 0; GetWindowThreadProcessId(h, out p);
      foreach(int want in pids){ if((int)p == want){
        StringBuilder sb = new StringBuilder(300); GetWindowText(h, sb, 300);
        if(sb.ToString() == "EA"){ hit = h; return false; }
      } }
      return true;
    }, IntPtr.Zero);
    return hit;
  }
}
'@
$parent = [TW]::Find($pids)
if($parent -eq [IntPtr]::Zero){ 'EA window not found'; exit 1 }
$widget = [PM]::Find($parent, 'Chrome_RenderWidgetHostHWND')
if($widget -eq [IntPtr]::Zero){
  $widget = [PM]::Find($parent, 'Chrome_WidgetWin_0')   # CEF drops the render host on some navigations
  W 'render host absent - using Chrome_WidgetWin_0'
}
if($widget -eq [IntPtr]::Zero){ 'no CEF input target'; exit 1 }
[void][PM]::SetForegroundWindow($parent)
Start-Sleep -Milliseconds 300
W ("click ABS $X,$Y on widget=$widget")
[PM]::Click($widget, $X, $Y)
foreach($ch in $Text.ToCharArray()){
  [void][PM]::PostMessage($widget, 0x0102, ([IntPtr][int]$ch), [IntPtr]1)   # WM_CHAR
  Start-Sleep -Milliseconds 30
}
if($Enter){ [void][PM]::PostMessage($widget, 0x0100, ([IntPtr]0x0D), [IntPtr]1); [void][PM]::PostMessage($widget, 0x0101, ([IntPtr]0x0D), [IntPtr]1) }
W ('posted chars=' + $Text.Length)
Start-Sleep -Milliseconds 700
& (Join-Path $rit 'small_shot.ps1') -Scale 0.6