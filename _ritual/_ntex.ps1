$src = @'
using System;
using System.Runtime.InteropServices;
public static class NTEX
{
    [DllImport("ntdll.dll")] public static extern int NtReadVirtualMemoryEx(IntPtr h, IntPtr a, byte[] b, IntPtr n, uint f, out IntPtr g);
    [DllImport("ntdll.dll")] public static extern int NtReadVirtualMemoryEx(IntPtr h, IntPtr a, byte[] b, ulong n, ulong f, out ulong g);
    [DllImport("ntdll.dll")] public static extern int NtReadVirtualMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr g);
    [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string m);
    [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("ntdll.dll", EntryPoint="NtReadVirtualMemoryEx")] public static extern int Ex5(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr g);
    [DllImport("ntdll.dll", EntryPoint="NtReadVirtualMemoryEx")] public static extern int Ex7(IntPtr h, IntPtr a, byte[] b, IntPtr n, uint f, ulong x, out IntPtr g);
    public static string T5(IntPtr h, ulong a, int n)
    {
        byte[] b = new byte[n]; IntPtr g;
        int st = Ex5(h, (IntPtr)(long)a, b, (IntPtr)n, out g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + g.ToInt64();
    }
    public static string T7N(IntPtr h, ulong a, int n)
    {
        byte[] b = new byte[n]; IntPtr g;
        int st = Ex7(h, (IntPtr)(long)a, b, (IntPtr)n, 0, 0, out g);
        return "n=" + n + " st=0x" + ((uint)st).ToString("x8") + " b0=" + (n > 0 ? b[0].ToString("x2") : "");
    }
    public static string T7X(IntPtr h, ulong a)
    {
        byte[] b = new byte[4]; IntPtr g; g = IntPtr.Zero;
        int st = Ex7(h, (IntPtr)(long)a, b, (IntPtr)4, 0, 0, out g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + g.ToInt64()
            + " buf=" + b[0].ToString("x2") + b[1].ToString("x2") + b[2].ToString("x2") + b[3].ToString("x2");
    }
    [DllImport("ntdll.dll", EntryPoint="NtReadVirtualMemoryEx")] public static extern int Ex8(IntPtr h, IntPtr a, byte[] b, IntPtr n, uint f, ulong x, IntPtr g, ulong y);
    public static string T8X(IntPtr h, ulong a)
    {
        byte[] b = new byte[4]; byte[] gb = new byte[8];
        IntPtr g = Marshal.AllocHGlobal(8);
        int st = Ex8(h, (IntPtr)(long)a, b, (IntPtr)4, 0, 0, g, 0);
        long got = Marshal.ReadInt64(g);
        Marshal.FreeHGlobal(g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + got
            + " buf=" + b[0].ToString("x2") + b[1].ToString("x2") + b[2].ToString("x2") + b[3].ToString("x2");
    }
    public static string T7(IntPtr h, ulong a, int n, ulong x)
    {
        byte[] b = new byte[n]; IntPtr g;
        int st = Ex7(h, (IntPtr)(long)a, b, (IntPtr)n, 0, x, out g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + g.ToInt64();
    }
    public static string Try(IntPtr h, ulong a, int n, uint f)
    {
        byte[] b = new byte[n]; IntPtr g;
        int st = NtReadVirtualMemoryEx(h, (IntPtr)(long)a, b, (IntPtr)n, f, out g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + g.ToInt64();
    }
    public static string Try2(IntPtr h, ulong a, int n)
    {
        byte[] b = new byte[n]; IntPtr g;
        int st = NtReadVirtualMemory(h, (IntPtr)(long)a, b, (IntPtr)n, out g);
        return "st=0x" + ((uint)st).ToString("x8") + " got=" + g.ToInt64();
    }
}
'@
Add-Type -TypeDefinition $src -Language CSharp

$n = [NTEX]::GetModuleHandle("ntdll.dll")
$p = [NTEX]::GetProcAddress($n, "NtReadVirtualMemoryEx")
$h = [NTEX]::OpenProcess(0x1F0FFF, $false, $PID)
$ksud = [uint64]0x7FFE0320
$ksud0 = [uint64]0x7FFE0000
$o = @()
$o += "ntdll=0x$($n.ToString('x')) export=0x$($p.ToString('x')) self=0x$($h.ToString('x')) pid=$PID"

foreach ($a in @($ksud, $ksud0)) {
    foreach ($f in @(0, 0x4000)) {
        $o += "ex a=0x$($a.ToString('x')) n=4 f=0x$($f.ToString('x')) -> " + [NTEX]::Try($h, $a, 4, $f)
        $o += "ex a=0x$($a.ToString('x')) n=1000 f=0x$($f.ToString('x')) -> " + [NTEX]::Try($h, $a, 0x1000, $f)
    }
    $o += "nt a=0x$($a.ToString('x')) n=4 -> " + [NTEX]::Try2($h, $a, 4)
}

$ex = (Get-Process explorer | Select-Object -First 1).Id
$h2 = [NTEX]::OpenProcess(0x1F0FFF, $false, $ex)
$h2h = $h2
$o += "explorer=0x$($h2.ToString('x'))"
$o += "ex @ksud -> " + [NTEX]::Try($h2, $ksud, 4, 0)
$o += "ex @ksud f4000 -> " + [NTEX]::Try($h2, $ksud, 4, 0x4000)
$o += "nt @ksud -> " + [NTEX]::Try2($h2, $ksud, 4)
$o += "t5 @ksud -> " + [NTEX]::T5($h, $ksud, 4)
$o += "t7 @ksud x0 -> " + [NTEX]::T7($h, $ksud, 4, 0)
$o += "t7 @ksud x1 -> " + [NTEX]::T7($h, $ksud, 4, 1)
$o += "t5 exp -> " + [NTEX]::T5($h2h, $ksud, 4)
$o += "t7 exp -> " + [NTEX]::T7($h2h, $ksud, 4, 0)
$o += "t7x self -> " + [NTEX]::T7X($h, $ksud)
$o += "t7x exp  -> " + [NTEX]::T7X($h2h, $ksud)
$o += "t8x self -> " + [NTEX]::T8X($h, $ksud)
$o += "t8x exp  -> " + [NTEX]::T8X($h2h, $ksud)
$o += "t7x exp @base? -> " + [NTEX]::T7X($h2h, $ksud)
$k0 = [uint64]0x7FFE0000
$o += "pg   " + [NTEX]::T7N($h, $k0, 0x1000)
$o += "pg4  " + [NTEX]::T7N($h, $k0, 4)
$o += "half " + [NTEX]::T7N($h, $k0, 0x800)
$o += "h2   " + [NTEX]::T7N($h, [uint64]0x7FFE0800, 0x800)
$o += "edge " + [NTEX]::T7N($h, [uint64](0x7FFE0FFC), 8)
$o += "in8  " + [NTEX]::T7N($h, [uint64](0x7FFE03FC), 8)
$o += "pgx  " + [NTEX]::T7N($h2h, $k0, 0x1000)
$o | Out-File -LiteralPath "$PSScriptRoot\_ntex_out.txt" -Encoding ascii
