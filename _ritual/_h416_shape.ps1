# _h416_shape - game-only. Enumeration works, reads return 0xc000000d; vary size/alignment/syscall.
# Prints full VAD info for the PEB and ksud so the page type is visible.
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h416_out.txt'
$src = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class S
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr n, out IntPtr got);
    [DllImport("ntdll.dll")] static extern int NtReadVirtualMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr n, out IntPtr got);
    [DllImport("ntdll.dll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr addr, int cls, ref MBI mbi, int len, out int ret);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi)] static extern IntPtr LoadLibrary(string n);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);

    delegate int Rve(IntPtr h, IntPtr a, byte[] b, IntPtr n, uint flags, out IntPtr got);

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

    static Rve _rve; static bool _rveTried;

    static string ViaNt(IntPtr h, ulong a, int n)
    {
        byte[] b = new byte[n]; IntPtr got;
        int st = NtReadVirtualMemory(h, (IntPtr)(long)a, b, (IntPtr)n, out got);
        return st == 0 ? "ok got=" + got.ToInt64() + " b0=" + b[0].ToString("x2") : "st=0x" + ((uint)st).ToString("x");
    }
    static string ViaEx(IntPtr h, ulong a, int n)
    {
        if (!_rveTried)
        {
            _rveTried = true;
            IntPtr m = LoadLibrary("ntdll.dll");
            IntPtr p = GetProcAddress(m, "NtReadVirtualMemoryEx");
            if (p != IntPtr.Zero) _rve = (Rve)Marshal.GetDelegateForFunctionPointer(p, typeof(Rve));
        }
        if (_rve == null) return "absent";
        byte[] b = new byte[n]; IntPtr got;
        int st = _rve(h, (IntPtr)(long)a, b, (IntPtr)n, 0, out got);
        return st == 0 ? "ok got=" + got.ToInt64() + " b0=" + b[0].ToString("x2") : "st=0x" + ((uint)st).ToString("x");
    }

    static string Vad(IntPtr h, ulong a)
    {
        MBI mb = new MBI(); int r2;
        int st = NtQueryVirtualMemory(h, (IntPtr)(long)a, 0, ref mb, Marshal.SizeOf(typeof(MBI)), out r2);
        if (st != 0) return "st=0x" + ((uint)st).ToString("x");
        return "base=0x" + mb.BaseAddress.ToInt64().ToString("x") + " alloc=0x" + mb.AllocationBase.ToInt64().ToString("x")
             + " sz=0x" + mb.RegionSize.ToInt64().ToString("x") + " st=0x" + mb.State.ToString("x")
             + " p=0x" + mb.Protect.ToString("x") + " t=0x" + mb.Type.ToString("x") + " ap=0x" + mb.AllocationProtect.ToString("x");
    }

    public static string Run(int pid)
    {
        StringBuilder o = new StringBuilder();
        uint[] accs = new uint[] { 0x10, 0x410 };
        foreach (uint acc in accs)
        {
            IntPtr h = OpenProcess(acc, false, pid);
            string tag = "acc=0x" + acc.ToString("x");
            if (h == IntPtr.Zero) { o.AppendLine(tag + " open err=" + Marshal.GetLastWin32Error()); continue; }
            PBI pbi = new PBI(); int ret;
            int stq = NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret);
            if (stq != 0) { o.AppendLine(tag + " ntqip st=0x" + ((uint)stq).ToString("x")); CloseHandle(h); continue; }
            ulong peb = (ulong)pbi.PebBaseAddress.ToInt64();
            o.AppendLine(tag + " peb=0x" + peb.ToString("x"));
            o.AppendLine(tag + " vad@ksud: " + Vad(h, 0x7FFE0000UL));
            o.AppendLine(tag + " vad@peb:  " + Vad(h, peb));
            ulong page = 0x7FFE0000UL;
            o.AppendLine(tag + " sz1   nt=" + ViaNt(h, page, 1) + " ex=" + ViaEx(h, page, 1));
            o.AppendLine(tag + " sz2   nt=" + ViaNt(h, page, 2));
            o.AppendLine(tag + " sz8   nt=" + ViaNt(h, page, 8));
            o.AppendLine(tag + " sz16  nt=" + ViaNt(h, page, 0x10));
            o.AppendLine(tag + " sz4kPA nt=" + ViaNt(h, page, 0x1000));
            o.AppendLine(tag + " sz4kEx nt=" + ViaEx(h, page, 0x1000));
            o.AppendLine(tag + " off+4 nt=" + ViaNt(h, page + 4, 4) + " @peb nt=" + ViaNt(h, peb + 0x10, 8) + " @peb4k nt=" + ViaNt(h, peb, 0x1000));
            CloseHandle(h);
        }
        return o.ToString();
    }
}
'@

Add-Type -TypeDefinition $src
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("is64=" + [Environment]::Is64BitProcess + " admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$p = Get-Process -Name 'r5apex_dx12' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { [void]$sb.Append([S]::Run($p.Id)) } else { [void]$sb.AppendLine("r5apex_dx12 : not running") }
$sb.ToString() | Out-File -LiteralPath $o -Encoding ascii
