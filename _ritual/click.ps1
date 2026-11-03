param([int]$X, [int]$Y, [string]$Key = '', [string]$Raise = '')
Add-Type @'
using System; using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
}
'@
if($Raise){
  $ws = New-Object -ComObject WScript.Shell
  [void]$ws.AppActivate($Raise)
  Start-Sleep -Milliseconds 600
}
if($Key){
  [M]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)          # alt down (focus anchor)
  Start-Sleep -Milliseconds 60
  [M]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
  $vk = [int][char]$Key.ToUpper()
  [M]::keybd_event([byte]$vk, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 40
  [M]::keybd_event([byte]$vk, 0, 2, [IntPtr]::Zero)
  "key $Key sent at $X,$Y"
} else {
  [void][M]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 120
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 60
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  "click $X,$Y"
}
