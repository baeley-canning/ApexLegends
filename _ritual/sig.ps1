# sig.ps1 - real input to a window: forced foreground + SendInput mouse click / ENTER key.
# pm_click.ps1 posts WM_LBUTTON* messages, which CEF dialogs inside the EA app ignore. This uses
# actual cursor + injected mouse events (hit testing, not message routing) and real key events.
#   -Act click -X <screenX> -Y <screenY>   (clicks the window under/containing that point)
#   -Act key   -Key ENTER|ESC|TAB|SPACE    (keys go to the forced-foreground window)
# Picks, among windows titled $Title, the one whose rect contains the point (else the first),
# so in-app modal dialogs on top of the same process are targeted correctly.
param([string]$Act = 'click', [int]$X = 0, [int]$Y = 0, [string]$Key = 'ENTER',
      [string]$Title = 'EA', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_sig.txt')
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class S {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx,dy; public uint md,dw,t; public IntPtr ex; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int x,y; }
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort wVk,wScan; public uint dw,t; public IntPtr ex; }
  [StructLayout(LayoutKind.Explicit)] public struct IN { [FieldOffset(0)] public uint type; [FieldOffset(4)] public MI mi; [FieldOffset(4)] public KI ki; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, IN[] a, int sz);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public static IntPtr Hit;
  public static bool Cb(IntPtr h, IntPtr p){
    if(!IsWindowVisible(h)) return true;
    var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
    if(sb.ToString() != T) return true;
    RECT r; GetWindowRect(h, out r);
    if(X >= r.L && X <= r.R && Y >= r.T && Y <= r.B){ Hit = h; return false; }
    if(Hit == IntPtr.Zero) Hit = h;
    return true;
  }
  public static string T = "";
  public static int X = 0, Y = 0;
  public static void Force(IntPtr h){
    IntPtr fg = GetForegroundWindow();
    uint ft = GetWindowThreadProcessId(fg, IntPtr.Zero), mt = GetCurrentThreadId();
    AttachThreadInput(mt, ft, true); SetForegroundWindow(h); BringWindowToTop(h); AttachThreadInput(mt, ft, false);
  }
  public static uint Click(){
    PT old; GetCursorPos(out old);
    SetCursorPos(X, Y);
    System.Threading.Thread.Sleep(80);
    IN dn = new IN(); dn.type = 0; dn.mi.dw = 0x0002;      // LEFTDOWN
    IN up = new IN(); up.type = 0; up.mi.dw = 0x0004;      // LEFTUP
    uint r = SendInput(1, new IN[]{ dn }, Marshal.SizeOf(typeof(IN)));
    System.Threading.Thread.Sleep(60);
    r += SendInput(1, new IN[]{ up }, Marshal.SizeOf(typeof(IN)));
    System.Threading.Thread.Sleep(120); SetCursorPos(old.X, old.Y);
    return r;
  }
  public static uint Key(ushort vk){
    IN d = new IN(); d.type = 1; d.ki.wVk = vk;
    IN u = new IN(); u.type = 1; u.ki.wVk = vk; u.ki.dw = 0x0002;
    SendInput(2, new IN[]{ d, u }, Marshal.SizeOf(typeof(IN)));
    return 2;
  }
}
'@
[S]::T = $Title
[S]::X = $X; [S]::Y = $Y
[void][S]::EnumWindows([S+EnumProc]{ param($h,$p) [S]::Cb($h,$p) }, [IntPtr]::Zero)
if([S]::Hit -eq [IntPtr]::Zero){ "window '$Title' not found" | Set-Content -LiteralPath $Out; exit 1 }
[S]::Force([S]::Hit)
Start-Sleep -Milliseconds 150
if($Act -eq 'click'){ $n = [S]::Click(); "click $X,$Y hwnd=$([S]::Hit) events=$n" | Set-Content -LiteralPath $Out }
else {
  $vk = @{ 'ENTER' = 0x0D; 'ESC' = 0x1B; 'TAB' = 0x09; 'SPACE' = 0x20 }[$Key.ToUpper()]
  $n = [S]::Key([uint16]$vk); "key $Key hwnd=$([S]::Hit) events=$n" | Set-Content -LiteralPath $Out
}
