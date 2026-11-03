# _u5.ps1 - which desktop is receiving input, is the EA window iconic/hidden?
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u5.txt'
"=== u5 $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class D5 {
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint f, bool inh, uint acc);
  [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenDesktop(string name, uint f, bool inh, uint acc);
  [DllImport("user32.dll")] public static extern bool GetUserObjectInformation(IntPtr h, int i, StringBuilder b, int n, out int need);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint t);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Name(IntPtr h){
    if(h == IntPtr.Zero) return "<null>";
    StringBuilder b = new StringBuilder(256); int n;
    if(!GetUserObjectInformation(h, 2, b, 512, out n)) return "<err " + Marshal.GetLastWin32Error() + ">";
    return b.ToString();
  }
}
'@
$inp = [D5]::OpenInputDesktop(0, $false, 0x0001)
W ("input desktop  = " + [D5]::Name($inp) + " h=" + $inp)
if($inp -ne [IntPtr]::Zero){ [void][D5]::CloseDesktop($inp) }
W ("our desktop    = " + [D5]::Name([D5]::GetThreadDesktop([D5]::GetCurrentThreadId())))
W ("shell window   = " + [D5]::GetShellWindow())
W ("foreground     = " + [D5]::GetForegroundWindow())
$p = New-Object D5+POINT; [void][D5]::GetCursorPos([ref]$p)
W ("cursor         = " + $p.X + "," + $p.Y)
W ("EA 67524 iconic=" + [D5]::IsIconic([IntPtr]67524) + " vis=" + [D5]::IsWindowVisible([IntPtr]67524))
W ("Code 262304 iconic=" + [D5]::IsIconic([IntPtr]262304) + " vis=" + [D5]::IsWindowVisible([IntPtr]262304))
Get-Content -LiteralPath $log
