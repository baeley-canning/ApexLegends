# paste.ps1 - put a string on the clipboard and send Ctrl+V, optionally after clicking a field.
# Used for the EA signup form: sendkey.ps1 only maps a few keys, addresses have letters/@/dots.
param([string]$Text = '', [int]$X = -1, [int]$Y = -1,
      [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_paste.txt')
if ($Text) { Set-Clipboard -Value $Text }
if ($X -ge 0) {
  Add-Type @'
using System; using System.Runtime.InteropServices;
public class PM {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
}
'@
  [void][PM]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 150
  [PM]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 60
  [PM]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 250
}
Add-Type @'
using System; using System.Runtime.InteropServices;
public class PK {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
}
'@
[PK]::keybd_event(0x11, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 50
[PK]::keybd_event(0x56, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 50
[PK]::keybd_event(0x56, 0, 2, [IntPtr]::Zero); Start-Sleep -Milliseconds 50
[PK]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 400
"pasted [$Text] at $X,$Y" | Set-Content -LiteralPath $Out
