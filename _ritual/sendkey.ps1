# sendkey.ps1 - send key taps by virtual key. Keys are comma separated, e.g. 'TAB,6,ENTER'.
# 19/11: this used to SendInput scan codes only (wVk=0 + KEYEVENTF_SCANCODE). EA's CEF signup
# form ignored them - Month/Day/Year stayed on placeholder - so it now uses keybd_event with a
# real virtual key. Scancode mode is gone; every caller passes key names, not scan codes.
param([string]$Keys = 'SPACE', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_sk.txt')
if (-not ('SK' -as [type])) {
Add-Type @'
using System; using System.Runtime.InteropServices;
public class SK {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  public static void Tap(byte vk) {
    keybd_event(vk, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(35);
    keybd_event(vk, 0, 2, IntPtr.Zero);
  }
}
'@
}
$map = @{ 'SPACE' = 0x20; 'ENTER' = 0x0D; 'TAB' = 0x09; 'ESC' = 0x1B; 'A' = 0x41;
          'DOWN' = 0x28; 'UP' = 0x26; 'LEFT' = 0x25; 'RIGHT' = 0x27; 'HOME' = 0x24; 'END' = 0x23;
          'DEL' = 0x2E; 'BACK' = 0x08;
          '0' = 0x30; '1' = 0x31; '2' = 0x32; '3' = 0x33; '4' = 0x34;
          '5' = 0x35; '6' = 0x36; '7' = 0x37; '8' = 0x38; '9' = 0x39 }
$n = 0
foreach ($k in ($Keys -split ',')) {
  $k = $k.Trim().ToUpper()
  if ($map.ContainsKey($k)) { [SK]::Tap([byte]$map[$k]); $n++; Start-Sleep -Milliseconds 150 }
}
"keys=$Keys events=$n" | Set-Content -LiteralPath $Out
