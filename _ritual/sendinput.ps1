param([int]$X = 963, [int]$Y = 578, [string]$Out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_si.txt')
Add-Type @'
using System; using System.Runtime.InteropServices;
public class SI {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(4)] public MOUSEINPUT mi; [FieldOffset(4)] public KEYBDINPUT ki; [FieldOffset(4)] public HARDWAREINPUT hi; }
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] a, int size);
  public const uint MOUSEEVENTF_MOVE = 0x0001, MOUSEEVENTF_ABSOLUTE = 0x8000, DOWN = 0x0002, UP = 0x0004;
  static INPUT M(int dx, int dy, uint f) { INPUT i = new INPUT(); i.type = 0; i.mi.dx = dx; i.mi.dy = dy; i.mi.dwFlags = f; return i; }
  public static uint ClickAbs(int sx, int sy, int w, int h) {
    int ax = (int)((sx - 3) * 65535.0 / (w - 1));
    int ay = (int)((sy - 3) * 65535.0 / (h - 1));
    int bx = (int)(sx * 65535.0 / (w - 1));
    int by = (int)(sy * 65535.0 / (h - 1));
    INPUT[] a = new INPUT[] {
      M(ax, ay, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE),
      M(bx, by, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE),
      M(0, 0, DOWN), M(0, 0, UP)
    };
    return SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
$w = 1920; $h = 1080
$n = [SI]::ClickAbs($X, $Y, $w, $h)
"SendInput events=$n target=$X,$Y (of ${w}x${h})" | Set-Content -LiteralPath $Out
