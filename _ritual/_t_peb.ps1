# _t_peb - prove BaseViaPeb logic (PEB+0x10 -> ImageBaseAddress -> MZ) on an openable target
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_t_peb.txt'
$src = @'
using System;
using System.Runtime.InteropServices;

public static class P
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr n, out IntPtr got);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
    [DllImport("ntdll.dll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr addr, int cls, ref MBI mbi, int len, out int ret);

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

    static byte[] Read(IntPtr h, ulong addr, int n)
    {
        byte[] b = new byte[n]; IntPtr got;
        if (ReadProcessMemory(h, (IntPtr)(long)addr, b, (IntPtr)n, out got) && got.ToInt64() == n) return b;
        return null;
    }

    public static string Probe(string label, int pid)
    {
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) return label + ": open err=" + Marshal.GetLastWin32Error();
        try
        {
            string r = label + ": ksud=" + (Read(h, 0x7FFE0000UL, 4) == null ? "FAIL" : "ok");
            PBI pbi = new PBI(); int ret;
            int st = NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret);
            if (st != 0) return r + " ntquery st=0x" + st.ToString("x");
            r += " peb=0x" + pbi.PebBaseAddress.ToInt64().ToString("x");
            byte[] b = Read(h, (ulong)pbi.PebBaseAddress.ToInt64() + 0x10, 8);
            if (b == null) return r + " peb unreadable";
            ulong bas = BitConverter.ToUInt64(b, 0);
            r += " imagebase=0x" + bas.ToString("x");
            byte[] mz = Read(h, bas, 2);
            if (mz == null) return r + " imagebase unreadable";
            return r + (mz[0] == 0x4d && mz[1] == 0x5a ? " MZ=OK" : " MZ=BAD " + mz[0].ToString("x2") + mz[1].ToString("x2"));
        }
        finally { CloseHandle(h); }
    }
    public static string VaScan(string label, int pid)
    {
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) return label + ": open err=" + Marshal.GetLastWin32Error();
        try
        {
            ulong a = 0x10000UL, best = 0, bestSz = 0;
            int regions = 0, imgs = 0;
            while (a < 0x7FFFFFFEFFFFUL)
            {
                MBI mb = new MBI(); int ret;
                int st = NtQueryVirtualMemory(h, (IntPtr)(long)a, 0, ref mb, Marshal.SizeOf(typeof(MBI)), out ret);
                if (st != 0) return label + ": ntqvm st=0x" + st.ToString("x") + " at 0x" + a.ToString("x");
                ulong sz = (ulong)mb.RegionSize.ToInt64();
                if (sz == 0) break;
                if (mb.State == 0x1000 && mb.Type == 0x1000000 && sz >= 0x1000)
                {
                    regions++;
                    byte[] hb = Read(h, a, 0x400);
                    if (hb != null && hb[0] == 0x4d && hb[1] == 0x5a)
                    {
                        int lf = BitConverter.ToInt32(hb, 0x3c);
                        if (lf > 0 && lf < 0x3c0 && hb[lf] == 0x50 && hb[lf + 1] == 0x45 && hb[lf + 2] == 0 && hb[lf + 3] == 0)
                        {
                            ushort magic = BitConverter.ToUInt16(hb, lf + 0x18);
                            uint soi = BitConverter.ToUInt32(hb, lf + 0x50);
                            if (magic == 0x20b && soi > 0x100000u && soi <= sz)
                            {
                                imgs++;
                                if ((ulong)soi > bestSz) { bestSz = soi; best = a; }
                            }
                        }
                    }
                }
                a += sz;
            }
            if (best == 0) return label + ": regions=" + regions + " cand=" + imgs + " NONE";
            return label + ": regions=" + regions + " cand=" + imgs + " best=0x" + best.ToString("x") + " size=0x" + bestSz.ToString("x");
        }
        finally { CloseHandle(h); }
    }
}
'@

Add-Type -TypeDefinition $src
$lines = @("is64=" + [Environment]::Is64BitProcess)
foreach ($n in 'explorer', 'r5apex_dx12') {
    $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { $lines += [P]::Probe($n + '(' + $p.Id + ')', $p.Id); $lines += [P]::VaScan($n + '(' + $p.Id + ')', $p.Id) } else { $lines += "$n : not running" }
}
$lines -join "`r`n" | Out-File -LiteralPath $o -Encoding ascii
