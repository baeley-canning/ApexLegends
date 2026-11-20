# _h415_rpm - find which read route EAC tolerates: k32 RPM vs ntdll NtReadVirtualMemory,
# across handle access levels and size-argument widths. Control = self + explorer.
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h415_out.txt'
$src = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class R
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr n, out IntPtr got);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int n, out UIntPtr got);
    [DllImport("ntdll.dll")] static extern int NtReadVirtualMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr n, out IntPtr got);
    [DllImport("ntdll.dll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr addr, int cls, ref MBI mbi, int len, out int ret);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);

    [StructLayout(LayoutKind.Sequential)]
    struct MBI
    {
        public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect;
        public ushort PartitionId; public IntPtr RegionSize; public uint State; public uint Protect; public uint Type;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PBI
    {
        public IntPtr ExitStatus; public IntPtr PebBaseAddress; public IntPtr AffinityMask;
        public IntPtr BasePriority; public IntPtr UniqueProcessId; public IntPtr InheritedFromUniqueProcessId;
    }

    static string Nt(IntPtr h, ulong a, int n)
    {
        byte[] b = new byte[n]; IntPtr got;
        int st = NtReadVirtualMemory(h, (IntPtr)(long)a, b, (IntPtr)n, out got);
        if (st != 0) return "st=0x" + ((uint)st).ToString("x");
        return "ok " + b[0].ToString("x2") + b[1].ToString("x2") + " got=" + got.ToInt64();
    }

    static string Kwp(IntPtr h, ulong a, int n, bool wide)
    {
        byte[] b = new byte[n];
        if (wide)
        {
            IntPtr got;
            if (!ReadProcessMemory(h, (IntPtr)(long)a, b, (IntPtr)n, out got)) return "err=" + Marshal.GetLastWin32Error();
            return "ok " + b[0].ToString("x2") + b[1].ToString("x2");
        }
        UIntPtr g2;
        if (!ReadProcessMemory(h, (IntPtr)(long)a, b, n, out g2)) return "err=" + Marshal.GetLastWin32Error();
        return "ok " + b[0].ToString("x2") + b[1].ToString("x2");
    }

    public static string Matrix(string label, int pid)
    {
        StringBuilder o = new StringBuilder();
        o.AppendLine("== " + label + " pid=" + pid + " ==");
        IntPtr hSelf = (IntPtr)(-1);
        o.AppendLine("self control: nt=" + Nt(hSelf, 0x7FFE0000UL, 4) + " rpm64=" + Kwp(hSelf, 0x7FFE0000UL, 4, true) + " rpm32=" + Kwp(hSelf, 0x7FFE0000UL, 4, false));
        uint[] accs = new uint[] { 0x0410, 0x0438, 0x1F0FFF };
        foreach (uint acc in accs)
        {
            IntPtr h = OpenProcess(acc, false, pid);
            string tag = "acc=0x" + acc.ToString("x");
            if (h == IntPtr.Zero) { o.AppendLine(tag + " open err=" + Marshal.GetLastWin32Error()); continue; }
            PBI pbi = new PBI(); int ret;
            int st = NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret);
            ulong peb = st == 0 ? (ulong)pbi.PebBaseAddress.ToInt64() : 0;
            MBI mb = new MBI(); int r2;
            int qv = NtQueryVirtualMemory(h, (IntPtr)0x7FFE0000, 0, ref mb, Marshal.SizeOf(typeof(MBI)), out r2);
            o.AppendLine(tag + " peb=0x" + peb.ToString("x") + " qvm@ksud=" + (qv == 0 ? "ok state=0x" + mb.State.ToString("x") + " p=0x" + mb.Protect.ToString("x") : "st=0x" + ((uint)qv).ToString("x")));
            o.AppendLine(tag + " ksud nt=" + Nt(h, 0x7FFE0000UL, 4) + " rpm64=" + Kwp(h, 0x7FFE0000UL, 4, true) + " rpm32=" + Kwp(h, 0x7FFE0000UL, 4, false));
            if (peb != 0)
            {
                o.AppendLine(tag + " pebfield nt=" + Nt(h, peb + 0x10, 8));
                byte[] bb = new byte[8]; IntPtr got;
                if (NtReadVirtualMemory(h, (IntPtr)(long)(peb + 0x10), bb, (IntPtr)8, out got) == 0)
                {
                    ulong bas = BitConverter.ToUInt64(bb, 0);
                    o.AppendLine(tag + " imagebase=0x" + bas.ToString("x") + " mz nt=" + (bas == 0 ? "-" : Nt(h, bas, 2)) + " rpm64=" + (bas == 0 ? "-" : Kwp(h, bas, 2, true)));
                }
            }
            CloseHandle(h);
        }
        return o.ToString();
    }
}
'@

Add-Type -TypeDefinition $src
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("is64=" + [Environment]::Is64BitProcess + " admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
foreach ($n in 'r5apex_dx12', 'explorer') {
    $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { [void]$sb.Append([R]::Matrix($n, $p.Id)) } else { [void]$sb.AppendLine("$n : not running") }
}
$sb.ToString() | Out-File -LiteralPath $o -Encoding ascii
