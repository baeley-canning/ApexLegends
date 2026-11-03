# ea_unstick.ps1 - repair stuck mouse state left by an aborted synthetic-input run
# Releases stuck buttons, breaks window capture, lifts any BlockInput, unsticks modifiers.
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_unstick.txt'
"=== unstick $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }

Add-Type @'
using System; using System.Runtime.InteropServices;
public class U {
  [DllImport("user32.dll")] public static extern IntPtr GetCapture();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern System.IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool BlockInput(bool b);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
'@
$MOUSEUP = @{ 'LEFT' = 0x0004; 'RIGHT' = 0x0010; 'MIDDLE' = 0x0020 }

# 0. log the picture before touching anything
$fg = [U]::GetForegroundWindow(); $cap = [U]::GetCapture()
$pt = New-Object U+POINT; [void][U]::GetCursorPos([ref]$pt)
$hit = [U]::WindowFromPoint($pt)
function Cls($h){ $sb = New-Object System.Text.StringBuilder 256; [void][U]::GetClassName($h,$sb,256); $sb.ToString() }
W ("pre  fg=$fg cap=$cap cursor=$($pt.X),$($pt.Y) hit=$hit(" + (Cls $hit) + ")")
W ("pre  btn L=$([U]::GetAsyncKeyState(0x01) -band 0x8000) R=$([U]::GetAsyncKeyState(0x02) -band 0x8000) M=$([U]::GetAsyncKeyState(0x04) -band 0x8000)")
W ("pre  SHIFT=$([U]::GetAsyncKeyState(0x10) -band 0x8000) CTRL=$([U]::GetAsyncKeyState(0x11) -band 0x8000) ALT=$([U]::GetAsyncKeyState(0x12) -band 0x8000)")

# 1. lift BlockInput if a hung script left it on
W ("BlockInput(false) = " + [U]::BlockInput($false))

# 2. release every mouse button, twice, with a gap so the queue drains
for($i=0; $i -lt 2; $i++){
  [U]::mouse_event($MOUSEUP['LEFT'],  0,0,0,[IntPtr]::Zero)
  [U]::mouse_event($MOUSEUP['RIGHT'], 0,0,0,[IntPtr]::Zero)
  [U]::mouse_event($MOUSEUP['MIDDLE'],0,0,0,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 120
}
W 'released L/R/M x2'

# 3. release modifier keys and Windows keys
foreach($vk in 0x10,0x11,0x12,0x5B,0x5C,0xA0,0xA1,0xA2,0xA3,0xA4,0xA5){
  [U]::keybd_event([byte]$vk, 0, 2, [IntPtr]::Zero)   # KEYEVENTF_KEYUP
}
W 'released modifiers + win keys'

# 4. break capture: whoever holds it gets LBUTTONUP + CANCELMODE, then the fg window too
foreach($h in @($cap, $fg, [U]::GetForegroundWindow()) | Where-Object { $_ -ne [IntPtr]::Zero } | Select-Object -Unique){
  [void][U]::PostMessage($h, 0x0202, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_LBUTTONUP
  [void][U]::PostMessage($h, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CANCELMODE
  W "cancelmode+lbup -> $h (" + (Cls $h) + ")"
}

# 5. a nudge: press/release the real left button once through SendInput, then bring the fg window back
[U]::mouse_event(0x0002, 0,0,0,[IntPtr]::Zero)   # LEFTDOWN
Start-Sleep -Milliseconds 60
[U]::mouse_event(0x0004, 0,0,0,[IntPtr]::Zero)   # LEFTUP
if($fg -ne [IntPtr]::Zero){ [void][U]::SetForegroundWindow($fg) }
W 'nudge click sent'

# 6. kill helper scripts that may still be mid-run (only exact helper names)
$stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
  Where-Object { $_.CommandLine -match '_(ritual\\\\)*(ea_post|ea_type|ea_signin|ea_uia|sendkey|small_shot)\.ps1' })
foreach($s in $stale){
  try { Stop-Process -Id $s.ProcessId -Force -ErrorAction Stop; W "killed $($s.ProcessId)" }
  catch { W "kill failed $($s.ProcessId): $($_.Exception.Message)" }
}
if(-not $stale.Count){ W 'no stale helper processes' }

Start-Sleep -Milliseconds 400

# 7. read back the state we care about
$pt2 = New-Object U+POINT; [void][U]::GetCursorPos([ref]$pt2)
$hit2 = [U]::WindowFromPoint($pt2)
W ("post cap=$([U]::GetCapture()) fg=$([U]::GetForegroundWindow()) hit=$hit2(" + (Cls $hit2) + ")")
W ("post btn L=$([U]::GetAsyncKeyState(0x01) -band 0x8000) R=$([U]::GetAsyncKeyState(0x02) -band 0x8000) M=$([U]::GetAsyncKeyState(0x04) -band 0x8000)")
W ("post SHIFT=$([U]::GetAsyncKeyState(0x10) -band 0x8000) CTRL=$([U]::GetAsyncKeyState(0x11) -band 0x8000) ALT=$([U]::GetAsyncKeyState(0x12) -band 0x8000)")
if([U]::GetCapture() -eq [IntPtr]::Zero){ W 'VERDICT: capture clear' } else { W 'VERDICT: capture STILL HELD' }
if(([U]::GetAsyncKeyState(0x01) -band 0x8000) -eq 0){ W 'VERDICT: left button up' } else { W 'VERDICT: left button STILL DOWN' }
Get-Content -LiteralPath $log
