# h413 - baseline capture with corrected offsets (dm32-backed)
# health 0x330, team 0x340, shield 0x18C, visibilityFlags 0x338 (report only)
# handle-vs-pointer disambiguation: value < 0x10000 => handle, else pointer
#
# 64-bit guard: from a WOW64 caller psapi truncates module bases to 32 bits and
# LIST_MODULES_ALL fails 87, so re-exec under the real 64-bit host.
if (-not [Environment]::Is64BitProcess) {
    $p64 = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $p64)) { $p64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    & $p64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit
}
$ErrorActionPreference = 'Stop'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h413_out.txt'

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class M
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out UIntPtr read);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TP ns, int len, IntPtr prev, IntPtr rl);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("psapi.dll", SetLastError=true)] static extern bool EnumProcessModulesEx(IntPtr h, IntPtr[] mods, int cb, out int need, uint filter);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool GetModuleInformation(IntPtr h, IntPtr mod, out MODINFO mi, int cb);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, int pid);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool Module32FirstW(IntPtr snap, ref MODENT me);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool Module32NextW(IntPtr snap, ref MODENT me);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
    [DllImport("ntdll.dll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr addr, int cls, ref MBI mbi, int len, out int ret);

    [StructLayout(LayoutKind.Sequential)]
    struct MBI
    {
        public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect;
        public ushort PartitionId; public IntPtr RegionSize; public uint State; public uint Protect; public uint Type;
    }

    [StructLayout(LayoutKind.Sequential)] struct TP { public int Count; public long Luid; public int Attr; }
    [StructLayout(LayoutKind.Sequential)] struct MODINFO { public IntPtr Base; public IntPtr Size; public IntPtr Entry; }
    [StructLayout(LayoutKind.Sequential)]
    struct PBI
    {
        public IntPtr ExitStatus; public IntPtr PebBaseAddress; public IntPtr AffinityMask;
        public IntPtr BasePriority; public IntPtr UniqueProcessId; public IntPtr InheritedFromUniqueProcessId;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct MODENT
    {
        public uint dwSize; public uint th32ModuleID; public uint th32ProcessID;
        public uint GlblcntUsage; public uint ProccntUsage;
        public IntPtr modBaseAddr; public uint modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szExePath;
    }

    public static IntPtr H = IntPtr.Zero;
    public static ulong Base;
    public static int Pid;

    public static string SetDebug()
    {
        IntPtr tok;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return "OpenProcessToken err=" + Marshal.GetLastWin32Error();
        long luid;
        if (!LookupPrivilegeValue(null, "SeDebugPrivilege", out luid)) return "LookupPrivilegeValue err=" + Marshal.GetLastWin32Error();
        TP tp = new TP(); tp.Count = 1; tp.Luid = luid; tp.Attr = 2;
        if (!AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return "Adjust err=" + Marshal.GetLastWin32Error();
        int e = Marshal.GetLastWin32Error();
        return e == 0 ? "ok" : "adjusted-with-warning err=" + e;
    }

    public static string Open(int pid)
    {
        Pid = pid;
        H = OpenProcess(0x0410, false, pid);
        if (H != IntPtr.Zero) return "ok (Q_INFO|VM_READ)";
        string ev = "0x0410 failed err=" + Marshal.GetLastWin32Error();
        H = OpenProcess(0x1000, false, pid);
        return H == IntPtr.Zero ? ev + "; 0x1000 failed err=" + Marshal.GetLastWin32Error() : ev + "; limited-only";
    }

    static string BaseViaToolhelp()
    {
        IntPtr snap = CreateToolhelp32Snapshot(0x08 | 0x10, Pid);
        if (snap == new IntPtr(-1)) return "snapshot err=" + Marshal.GetLastWin32Error();
        MODENT me = new MODENT();
        me.dwSize = (uint)Marshal.SizeOf(typeof(MODENT));
        try
        {
            if (!Module32FirstW(snap, ref me)) return "Module32First err=" + Marshal.GetLastWin32Error();
            do
            {
                if (string.Equals(me.szModule, "r5apex_dx12.exe", StringComparison.OrdinalIgnoreCase))
                {
                    Base = (ulong)me.modBaseAddr.ToInt64();
                    return "ok(toolhelp) base=0x" + Base.ToString("x") + " size=0x" + me.modBaseSize.ToString("x");
                }
            } while (Module32NextW(snap, ref me));
            return "no matching module";
        }
        finally { CloseHandle(snap); }
    }

    static string BaseViaPeb()
    {
        byte[] ks = Read(0x7FFE0000UL, 4);
        string pre = ks == null ? "rpm@ksud err=" + LastReadErr : "rpm@ksud ok";
        PBI pbi = new PBI();
        int ret;
        int st = NtQueryInformationProcess(H, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret);
        if (st != 0) return pre + "; ntquery st=0x" + st.ToString("x");
        if (pbi.PebBaseAddress == IntPtr.Zero) return pre + "; peb null";
        byte[] b = Read((ulong)pbi.PebBaseAddress.ToInt64() + 0x10, 8);
        if (b == null) return pre + "; peb unreadable err=" + LastReadErr + " at 0x" + pbi.PebBaseAddress.ToInt64().ToString("x");
        Base = BitConverter.ToUInt64(b, 0);
        if (Base == 0) return pre + "; imagebase 0";
        byte[] mz = Read(Base, 2);
        if (mz == null) return pre + "; imagebase unreadable err=" + LastReadErr + " 0x" + Base.ToString("x");
        if (mz[0] != 0x4d || mz[1] != 0x5a) return pre + "; no MZ at 0x" + Base.ToString("x");
        return "ok(peb) base=0x" + Base.ToString("x");
    }

    // PEB-free: walk committed MEM_IMAGE regions and accept only a PE32+ header whose
    // SizeOfImage matches the reservation. EAC hides the module list; it does not hide VM.
    static string BaseViaVirtualScan()
    {
        ulong a = 0x10000UL, best = 0, bestSz = 0;
        int regions = 0, imgs = 0;
        while (a < 0x7FFFFFFEFFFFUL)
        {
            MBI mb = new MBI();
            int ret;
            int st = NtQueryVirtualMemory(H, (IntPtr)(long)a, 0, ref mb, Marshal.SizeOf(typeof(MBI)), out ret);
            if (st != 0) break;
            ulong sz = (ulong)mb.RegionSize.ToInt64();
            if (sz == 0) break;
            if (mb.State == 0x1000 && mb.Type == 0x1000000 && sz >= 0x1000)
            {
                regions++;
                byte[] h = Read(a, 0x400);
                if (h != null && h[0] == 0x4d && h[1] == 0x5a)
                {
                    int lf = BitConverter.ToInt32(h, 0x3c);
                    if (lf > 0 && lf < 0x3c0 && h[lf] == 0x50 && h[lf + 1] == 0x45 && h[lf + 2] == 0 && h[lf + 3] == 0)
                    {
                        ushort magic = BitConverter.ToUInt16(h, lf + 0x18);
                        uint soi = BitConverter.ToUInt32(h, lf + 0x50);
                        if (magic == 0x20b && soi > 0x8000000u && soi <= sz)
                        {
                            imgs++;
                            if ((ulong)soi > bestSz) { bestSz = soi; best = a; }
                        }
                    }
                }
            }
            a += sz;
        }
        if (best == 0) return "va-scan no image regions=" + regions + " cand=" + imgs;
        Base = best;
        return "ok(va-scan) base=0x" + best.ToString("x") + " size=0x" + bestSz.ToString("x") + " regions=" + regions;
    }

    public static string GetBase()
    {
        string peb = BaseViaPeb();
        if (peb.StartsWith("ok")) return peb;
        string why = "peb " + peb;
        string vs = BaseViaVirtualScan();
        if (vs.StartsWith("ok")) return vs + " [after " + why + "]";
        why += "; " + vs;
        IntPtr[] mods = new IntPtr[512];
        int need;
        if (EnumProcessModulesEx(H, mods, mods.Length * IntPtr.Size, out need, 3))
        {
            MODINFO mi;
            if (GetModuleInformation(H, mods[0], out mi, Marshal.SizeOf(typeof(MODINFO))))
            {
                Base = (ulong)mi.Base.ToInt64();
                return "ok(psapi) base=0x" + Base.ToString("x") + " size=0x" + ((ulong)mi.Size.ToInt64()).ToString("x");
            }
            why += "; GetModuleInformation err=" + Marshal.GetLastWin32Error();
        }
        else
        {
            int e1 = Marshal.GetLastWin32Error();
            why += "; EnumProcessModulesEx err=" + e1;
            // 87 on a 32-bit caller is the WOW64 case; LIST_MODULES_64BIT alone can still work
            if (e1 == 87)
            {
                int need2;
                if (EnumProcessModulesEx(H, mods, mods.Length * IntPtr.Size, out need2, 2))
                {
                    MODINFO mi2;
                    if (GetModuleInformation(H, mods[0], out mi2, Marshal.SizeOf(typeof(MODINFO))))
                    {
                        Base = (ulong)mi2.Base.ToInt64();
                        return "ok(psapi64only) base=0x" + Base.ToString("x") + " size=0x" + ((ulong)mi2.Size.ToInt64()).ToString("x");
                    }
                }
            }
        }
        string th = BaseViaToolhelp();
        if (th.StartsWith("ok")) return th + " [fallback after " + why + "]";
        return why + "; toolhelp " + th;
    }

    public static int LastReadErr;
    public static byte[] Read(ulong a, int n)
    {
        byte[] b = new byte[n];
        UIntPtr got;
        if (!ReadProcessMemory(H, (IntPtr)(long)a, b, (IntPtr)n, out got))
        {
            LastReadErr = Marshal.GetLastWin32Error();
            return null;
        }
        if ((int)got < n) { LastReadErr = -1; return null; }
        LastReadErr = 0;
        return b;
    }

    public static int I32(ulong a) { byte[] b = Read(a, 4); return b == null ? int.MinValue : BitConverter.ToInt32(b, 0); }
    public static ulong Q(ulong a) { byte[] b = Read(a, 8); return b == null ? 0 : BitConverter.ToUInt64(b, 0); }

    public static string Hex(ulong a, int n)
    {
        byte[] b = Read(a, n);
        if (b == null) return "<unreadable>";
        StringBuilder s = new StringBuilder();
        foreach (byte x in b) s.Append(x.ToString("x2"));
        return s.ToString();
    }

    static bool Printable(ulong a)
    {
        byte[] b = Read(a, 24);
        if (b == null || b[0] < 0x20 || b[0] > 0x7e) return false;
        int ok = 0;
        for (int i = 0; i < b.Length; i++) { if (b[i] == 0) return ok >= 3; if (b[i] >= 0x20 && b[i] < 0x7f) ok++; else return ok >= 3; }
        return ok >= 3;
    }

    static string Ascii(ulong a, int n)
    {
        byte[] b = Read(a, n);
        if (b == null) return "";
        StringBuilder s = new StringBuilder();
        foreach (byte x in b) { if (x == 0) break; if (x >= 0x20 && x < 0x7f) s.Append((char)x); else s.Append('.'); }
        return s.ToString();
    }

    // three-field AND: hp 1..250, team 0..30, printable signifier
    public static string Sig(ulong e, out int hp, out int team)
    {
        hp = I32(e + 0x330);
        team = I32(e + 0x340);
        if (hp == int.MinValue || hp < 1 || hp > 250) return "FAIL-hp";
        if (team == int.MinValue || team < 0 || team > 30) return "FAIL-team";
        ulong sp = Q(e + 0x478);
        if (sp == 0) return "FAIL-sig-null";
        if (!Printable(sp)) return "FAIL-sig-unprintable";
        return "OK";
    }

    public static string Report(int pid)
    {
        StringBuilder o = new StringBuilder();
        o.AppendLine("== privilege ==");
        o.AppendLine("SetDebugPrivilege: " + SetDebug());
        o.AppendLine("== open ==");
        o.AppendLine("OpenProcess(pid " + pid + "): " + Open(pid));
        if (H == IntPtr.Zero) return o.ToString();
        o.AppendLine("== base ==");
        o.AppendLine("module[0]: " + GetBase());
        if (Base == 0) return o.ToString();
        o.AppendLine("reader_valid: first2=" + Hex(Base, 2) + " (expect 4d5a)");

        ulong[] locals = new ulong[] { 0x26AF8A8, 0x24D1B80, 0x1ACDD08 };
        ulong[] lists = new ulong[] { 0x619AAA8, 0x6B51458, 0x6B53478 };

        o.AppendLine("== locals (value at base+rva) ==");
        foreach (ulong rva in locals)
        {
            ulong a = Base + rva;
            ulong v = Q(a);
            o.AppendLine("rva=0x" + rva.ToString("x") + " raw=0x" + v.ToString("x") + " ascii=\"" + Ascii(a, 12) + "\"");
            if (v == 0xccccccccccccccccUL) { o.AppendLine("  verdict=UNINITIALISED"); continue; }
            if (v < 0x10000UL) { o.AppendLine("  verdict=HANDLE index=" + (v - 1)); continue; }
            int hp, team;
            string s = Sig(v, out hp, out team);
            o.AppendLine("  verdict=PTR sig=" + s + " hp=" + hp + " team=" + team);
        }

        o.AppendLine("== lists ==");
        foreach (ulong rva in lists)
        {
            ulong arr = Q(Base + rva);
            o.AppendLine("rva=0x" + rva.ToString("x") + " array=0x" + arr.ToString("x"));
            if (arr == 0 || arr == 0xccccccccccccccccUL || arr < 0x10000) { o.AppendLine("  verdict=EMPTY/UNSET"); continue; }
            int valid = 0, shown = 0;
            StringBuilder rows = new StringBuilder();
            for (int i = 0; i < 64 && shown < 24; i++)
            {
                ulong v = Q(arr + (ulong)(i * 8));
                if (v == 0) continue;
                ulong e = v < 0x10000UL ? v - 1 : v;
                if (e == 0) continue;
                int hp, team;
                if (Sig(e, out hp, out team) != "OK") continue;
                valid++; shown++;
                ulong sp = Q(e + 0x478);
                byte[] xyz = Read(e + 0x170, 12);
                string pos = xyz == null ? "<x>" : (BitConverter.ToSingle(xyz,0).ToString("0.0") + "," + BitConverter.ToSingle(xyz,4).ToString("0.0") + "," + BitConverter.ToSingle(xyz,8).ToString("0.0"));
                rows.AppendLine("  [" + i + "] ent=0x" + e.ToString("x") + " hp=" + hp + " team=" + team
                    + " shield=" + I32(e + 0x18C) + "/" + I32(e + 0x190)
                    + " vis=0x" + I32(e + 0x338).ToString("x") + " nameIdx=" + I32(e + 0x481)
                    + " sig=\"" + Ascii(sp, 20) + "\" pos=" + pos);
            }
            o.AppendLine("  valid_slots=" + valid);
            o.Append(rows.ToString());
        }
        o.AppendLine("== done ==");
        return o.ToString();
    }
}
'@

try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
    $p = Get-Process -Name 'r5apex_dx12' -ErrorAction SilentlyContinue
    if (-not $p) {
        "RESULT=NO_GAME`nNo r5apex_dx12 process running." | Out-File -FilePath $out -Encoding ascii
    } else {
        $gpid = [int]$p[0].Id
        $body = [M]::Report($gpid)
        "pid=$gpid started=$(Get-Date -Format s)`n$body" | Out-File -FilePath $out -Encoding ascii
    }
    "rc=0" | Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h413_rc.txt' -Encoding ascii
    "WROTE $out"
} catch {
    "rc=1`n" + $_.Exception.Message | Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h413_rc.txt' -Encoding ascii
    "ERROR: " + $_.Exception.Message
}
