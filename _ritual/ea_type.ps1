# ea_type - focus EA's CEF render widget and type with unicode SendInput (no shift-state guessing).
# The sign-in form lives in Chrome_RenderWidgetHostHWND; SendKeys to the parent window goes nowhere.
param([string]$Text = '', [switch]$Enter)
$rit = $PSScriptRoot
$o   = Join-Path $rit 'ea_type.txt'
function W($t){ $t | Add-Content -LiteralPath $o; $t }
# EA Desktop runs elevated on this box, so injection from a medium-IL shell never lands: re-run elevated.
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Text',('"'+$Text+'"'))
  if($Enter){ $a += '-Enter' }
  Start-Process powershell -Verb RunAs -ArgumentList $a
  'elevating'; exit
}
Add-Type @'
using System; using System.Runtime.InteropServices;
public class U {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr after, string cls, string win);

  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(4)] public KEYBDINPUT ki; [FieldOffset(4)] public MOUSEINPUT mi; }
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] a, int size);

  public static void Char(char ch){
    INPUT d = new INPUT(); d.type = 1; d.ki.wVk = 0; d.ki.wScan = (ushort)ch; d.ki.dwFlags = 0x0004;
    INPUT u = new INPUT(); u.type = 1; u.ki.wVk = 0; u.ki.wScan = (ushort)ch; u.ki.dwFlags = 0x0004 | 0x0002;
    SendInput(2, new INPUT[] { d, u }, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(35);
  }
  public static void Key(ushort vk){
    INPUT d = new INPUT(); d.type = 1; d.ki.wVk = vk; d.ki.wScan = 0; d.ki.dwFlags = 0;
    INPUT u = new INPUT(); u.type = 1; u.ki.wVk = vk; u.ki.wScan = 0; u.ki.dwFlags = 0x0002;
    SendInput(2, new INPUT[] { d, u }, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(60);
  }
}
'@
$ea = @(Get-Process EADesktop -EA SilentlyContinue)
if(-not $ea.Count){ 'EA not running'; exit 1 }
$parent = [IntPtr]67524
# hierarchy is nested: Qt -> Qt5152QWindowIcon -> CefBrowserWindow -> Chrome_WidgetWin_0 -> render host
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class FC {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EP e, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static IntPtr Find(IntPtr root, string cls){
    IntPtr hit = IntPtr.Zero;
    EnumChildWindows(root, delegate(IntPtr h, IntPtr l){
      StringBuilder sb = new StringBuilder(200);
      GetClassName(h, sb, 200);
      if(sb.ToString() == cls){ hit = h; return false; }
      return true;
    }, IntPtr.Zero);
    return hit;
  }
}
'@
$widget = [FC]::Find($parent, 'Chrome_RenderWidgetHostHWND')
$render = [FC]::Find($parent, 'Chrome_WidgetWin_0')
if($widget -eq [IntPtr]::Zero){ 'CEF render widget not found'; exit 1 }
W ("render=$render widget=$widget")

# give the process input focus, then aim the render widget itself
$tid = 0
[void][U]::GetWindowThreadProcessId($parent, [ref]$tid)
$me = [U]::GetCurrentThreadId()
[void][U]::AttachThreadInput($me, $tid, $true)
[void][U]::SetForegroundWindow($parent)
[void][U]::SetFocus($widget)
[void][U]::AttachThreadInput($me, $tid, $false)
Start-Sleep -Milliseconds 400
W ('focus now=' + [U]::GetFocus())

foreach($ch in $Text.ToCharArray()){ [U]::Char($ch) }
if($Enter){ [U]::Key(0x0D) }
W ('typed len=' + $Text.Length + ' enter=' + [bool]$Enter)
Start-Sleep -Milliseconds 600
& (Join-Path $rit 'small_shot.ps1') -Scale 0.6