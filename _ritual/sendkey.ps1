param([string]$Keys = 'SPACE', [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_sk.txt')
Add-Type @'
using System; using System.Runtime.InteropServices;
public class SK {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(4)] public KEYBDINPUT ki; [FieldOffset(4)] public MOUSEINPUT mi; }
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] a, int size);
  public static uint Tap(ushort scan) {
    INPUT d = new INPUT(); d.type = 1; d.ki.wScan = scan; d.ki.dwFlags = 0x0008;
    INPUT u = new INPUT(); u.type = 1; u.ki.wScan = scan; u.ki.dwFlags = 0x0008 | 0x0002;
    INPUT[] a = new INPUT[] { d, u };
    return SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
$map = @{ 'SPACE' = 0x39; 'ENTER' = 0x1C; 'TAB' = 0x0F; 'ESC' = 0x01; 'A' = 0x1E }
$n = 0
foreach($k in ($Keys -split ',')){ $k = $k.Trim().ToUpper(); if($map.ContainsKey($k)){ $n += [SK]::Tap([uint16]$map[$k]); Start-Sleep -Milliseconds 220 } }
"keys=$Keys events=$n" | Set-Content -LiteralPath $Out
