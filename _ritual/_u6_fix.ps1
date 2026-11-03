# _u6_fix.ps1 - hard reset of the input state: capture, menu loops, stuck buttons, foreground
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u6.txt'
"=== u6 fix $(Get-Date -Format s) ===" | Set-Content -LiteralPath $log
function W($m){ $m | Add-Content -LiteralPath $log; $m }
Add-Type @'
using System; using System.Runtime.InteropServices;
public class F6 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern IntPtr GetCapture();
  [DllImport("user32.dll")] public static extern IntPtr ReleaseCapture();
  [DllImport("user32.dll")] public static extern bool EndMenu();
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
  [DllImport("user32.dll")] public static extern bool BlockInput(bool b);
  public static int BreakAll(){
    int n = 0; uint me = GetCurrentThreadId();
    EnumWindows(delegate(IntPtr h, IntPtr l){
      uint p = 0; uint t = GetWindowThreadProcessId(h, out p);
      if(t == 0 || t == me) return true;
      if(AttachThreadInput(me, t, true)){
        if(GetCapture() != IntPtr.Zero){ ReleaseCapture(); n++; }
        EndMenu();
        AttachThreadInput(me, t, false);
      }
      PostMessage(h, 0x001F, IntPtr.Zero, IntPtr.Zero);   // WM_CANCELMODE everywhere
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
'@
W ("BlockInput(false) prior=" + [F6]::BlockInput($false))

# unstuck buttons and wheel-ish residue
for($i=0; $i -lt 3; $i++){
  [F6]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)   # LEFTUP
  [F6]::mouse_event(0x0010,0,0,0,[IntPtr]::Zero)   # RIGHTUP
  [F6]::mouse_event(0x0020,0,0,0,[IntPtr]::Zero)   # MIDDLEUP
  Start-Sleep -Milliseconds 80
}
W 'buttons released x3'

# Esc twice cancels menus / drag / modal loops
foreach($i in 1,2){ [F6]::keybd_event(0x1B,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 40; [F6]::keybd_event(0x1B,0,2,[IntPtr]::Zero); Start-Sleep -Milliseconds 80 }
W 'esc x2'

# break any capture owned by another thread, cancel-mode every top-level
W ('captures released = ' + [F6]::BreakAll())
Start-Sleep -Milliseconds 200
W ('capture now = ' + [F6]::GetCapture())

# give focus back to a real app
$shell = [F6]::GetShellWindow()
[void][F6]::SetCursorPos(960, 600)
Start-Sleep -Milliseconds 120
[void][F6]::SetForegroundWindow($shell)
[void][F6]::BringWindowToTop([IntPtr]262304)
[void][F6]::SetForegroundWindow([IntPtr]262304)
[void][F6]::SetCursorPos(960, 540)
Start-Sleep -Milliseconds 300
W ('fg now = ' + [F6]::GetForegroundWindow() + ' (want 262304)')
W ('btn L=' + ([F6]::GetAsyncKeyState(0x01) -band 0x8000) + ' esc=' + ([F6]::GetAsyncKeyState(0x1B) -band 0x8000))
if([F6]::GetCapture() -eq [IntPtr]::Zero -and ([F6]::GetAsyncKeyState(0x01) -band 0x8000) -eq 0){ W 'VERDICT: release ok' } else { W 'VERDICT: still stuck' }
Get-Content -LiteralPath $log
