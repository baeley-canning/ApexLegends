param([switch]$ElevatedChild, [switch]$NoUac, [int]$PidOverride = 0, [switch]$Once, [switch]$Full, [int]$IntervalSec = 4)

# _run - single file, single UAC, whole pipeline, self-classifying.
# stages: privilege -> open -> read-shape matrix -> base -> MZ verify -> .data scan -> verdict
# verdict is always the last line of _report.txt: PIPELINE=OK or PIPELINE=BLOCKED block=<why>
# default is watch mode: the elevated window stays up and re-runs on pid change, so Apex
# restarts cost nothing. -Once runs a single pass. -Full scans .data's whole vsize.
if (-not [Environment]::Is64BitProcess) {
    $p64 = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $p64)) { $p64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($PidOverride) { $a += @('-PidOverride', [string]$PidOverride) }
    if ($Once) { $a += '-Once' }
    if ($Full) { $a += '-Full' }
    & $p64 @a
    exit
}

$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$rep = "$dir\_report.txt"
$log = "$dir\_report_log.txt"
$sta = "$dir\_run_status.txt"

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$dbgPriv = (& whoami /priv 2>$null | Select-String 'SeDebugPrivilege') -join ' '
if (-not $dbgPriv) { $dbgPriv = 'SeDebugPrivilege ABSENT' }

if (-not $adm -and -not $ElevatedChild -and -not $NoUac) {
    $ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    "unelevated start $(Get-Date -Format s) pid=$PID -> raising UAC" | Out-File -LiteralPath $sta -Encoding ascii
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ElevatedChild')
    if ($PidOverride) { $a += @('-PidOverride', [string]$PidOverride) }
    if ($Once) { $a += '-Once' }
    if ($Full) { $a += '-Full' }
    try { Start-Process -FilePath $ps64 -Verb RunAs -ArgumentList $a }
    catch { ("uac FAILED: " + $_.Exception.Message) | Add-Content -LiteralPath $sta -Encoding ascii }
    exit
}

"elevated start $(Get-Date -Format s) pid=$PID adm=$adm once=$($Once.IsPresent)" | Out-File -LiteralPath $sta -Encoding ascii
if (-not $adm -and -not $NoUac) { "no elevation and no uac - stop" | Add-Content -LiteralPath $sta -Encoding ascii; exit 1 }
$src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class R17
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out UIntPtr got);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint f, int pid);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool Module32FirstW(IntPtr s, ref MODENT m);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool Module32NextW(IntPtr s, ref MODENT m);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi)] static extern IntPtr LoadLibrary(string n);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TP ns, int len, IntPtr prev, IntPtr rl);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool EnumProcessModulesEx(IntPtr h, IntPtr[] mods, int cb, out int need, uint filter);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool GetModuleInformation(IntPtr h, IntPtr mod, out MODINFO mi, int cb);
    [DllImport("ntdll.dll")] static extern int NtReadVirtualMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr got);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int c, ref PBI p, int l, out int r);
    [DllImport("ntdll.dll", EntryPoint="NtQueryInformationProcess")] static extern int NtQueryInformationProcessB(IntPtr h, int c, byte[] p, int l, out int r);
    [DllImport("ntdll.dll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr a, int c, ref MBI m, int l, out int r);
    [DllImport("ntdll.dll", EntryPoint="NtQueryVirtualMemory")] static extern int NtQueryVirtualMemoryName(IntPtr h, IntPtr a, int c, byte[] m, int l, out int r);

    delegate int PFN_RVE(IntPtr h, IntPtr a, byte[] b, IntPtr n, uint f, ulong x, out IntPtr got);
    delegate int PFN_WOW(IntPtr h, ulong a, byte[] b, ulong n, out ulong got);
    static PFN_RVE _rve; static PFN_WOW _wow; static bool _res;

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
    public static ulong ImgEnd;
    public static uint Acc;
    public static string Mode = "";
    public static int LastReadErr;

    const ulong DATA_RVA   = 0x334C000;
    const ulong DATA_RAW   = 0xD00800;
    const ulong DATA_VSIZE = 0xAB23AAC;
    const int   BATCH      = 0x10000;
    const int   CAP        = 3000000;

    // every engine x {exact, page-aligned staging}; page staging is the fallback for
    // filters that only accept a whole aligned page. wow = NtWow64ReadVirtualMemory64.
    static string[] MODES = new string[] {
        "rpm_exact", "rpm_page", "nt_exact", "nt_page",
        "ntex_exact", "ntex_page", "wow_exact", "wow_page" };

    // winner preference: kernel-side syscalls first, since usermode RPM hooks are the
    // common filter. exact before page, because page staging masks width sensitivity.
    static string[] WIN = new string[] {
        "ntex_exact", "nt_exact", "ntex_page", "nt_page",
        "wow_exact", "wow_page", "rpm_exact", "rpm_page" };

    static void Resolve()
    {
        if (_res) return; _res = true;
        IntPtr m = LoadLibrary("ntdll.dll");
        IntPtr p1 = GetProcAddress(m, "NtReadVirtualMemoryEx");
        if (p1 != IntPtr.Zero) _rve = (PFN_RVE)Marshal.GetDelegateForFunctionPointer(p1, typeof(PFN_RVE));
        IntPtr p2 = GetProcAddress(m, "NtWow64ReadVirtualMemory64");
        if (p2 != IntPtr.Zero) _wow = (PFN_WOW)Marshal.GetDelegateForFunctionPointer(p2, typeof(PFN_WOW));
    }

    static IntPtr IP(ulong a) { return (IntPtr)unchecked((long)a); }
    static string Fmt(int e)
    {
        if (e == -2) return "absent";
        if (e == -3) return "engine?";
        return e < 0 ? "st=0x" + unchecked((uint)e).ToString("x8") : "err=" + e;
    }
    static bool Raw(string e, ulong a, byte[] b, int n)
    {
        LastReadErr = 0;
        switch (e)
        {
            case "rpm":
            {
                UIntPtr g;
                if (!ReadProcessMemory(H, IP(a), b, (IntPtr)n, out g)) { LastReadErr = Marshal.GetLastWin32Error(); return false; }
                return (int)g == n;
            }
            case "nt":
            {
                IntPtr g;
                int st = NtReadVirtualMemory(H, IP(a), b, (IntPtr)n, out g);
                if (st != 0) { LastReadErr = st; return false; }
                return g.ToInt64() == n;
            }
            case "ntex":
            {
                Resolve();
                if (_rve == null) { LastReadErr = -2; return false; }
                // 7-arg form: this build rejects the 6-arg shape with 0xc000000d.
                // this build also returns STATUS_PARTIAL_COPY whenever the request
                // crosses a page boundary, so chop at page edges and never pass a
                // straddling range. the 7th slot is not the byte count.
                int done = 0; ulong cur = a;
                while (done < n)
                {
                    int room = 0x1000 - (int)(cur & 0xFFFUL);
                    int want = room < n - done ? room : n - done;
                    IntPtr junk;
                    int st;
                    if (done == 0 && want == n) st = _rve(H, IP(cur), b, (IntPtr)want, 0, 0, out junk);
                    else
                    {
                        byte[] tmp = new byte[want];
                        st = _rve(H, IP(cur), tmp, (IntPtr)want, 0, 0, out junk);
                        if (st == 0) Buffer.BlockCopy(tmp, 0, b, done, want);
                    }
                    if (st != 0) { LastReadErr = st; return false; }
                    done += want; cur += (ulong)want;
                }
                return true;
            }
            case "wow":
            {
                Resolve();
                if (_wow == null) { LastReadErr = -2; return false; }
                ulong g;
                int st = _wow(H, a, b, (ulong)n, out g);
                if (st != 0) { LastReadErr = st; return false; }
                return (long)g == n;
            }
        }
        LastReadErr = -3;
        return false;
    }

    static byte[] ReadM(string mode, ulong a, int n)
    {
        if (n <= 0) return new byte[0];
        bool page = mode.EndsWith("_page");
        int u = mode.LastIndexOf('_');
        string eng = u > 0 ? mode.Substring(0, u) : mode;
        if (!page)
        {
            byte[] r = new byte[n];
            return Raw(eng, a, r, n) ? r : null;
        }
        byte[] b = new byte[n];
        int done = 0; ulong cur = a;
        while (done < n)
        {
            ulong pa = cur & ~0xFFFUL;
            int off = (int)(cur - pa);
            int want = 0x1000 - off;
            if (want > n - done) want = n - done;
            byte[] pg = new byte[0x1000];
            if (!Raw(eng, pa, pg, 0x1000)) return null;
            Buffer.BlockCopy(pg, off, b, done, want);
            done += want; cur += (ulong)want;
        }
        return b;
    }

    public static byte[] Read(ulong a, int n) { return ReadM(Mode, a, n); }
    public static int I32(ulong a) { byte[] b = Read(a, 4); return b == null ? int.MinValue : BitConverter.ToInt32(b, 0); }
    public static ulong Q(ulong a) { byte[] b = Read(a, 8); return b == null ? 0 : BitConverter.ToUInt64(b, 0); }

    public static string Ascii(ulong a, int n)
    {
        byte[] b = Read(a, n);
        if (b == null) return "";
        StringBuilder s = new StringBuilder();
        foreach (byte x in b) { if (x == 0) break; s.Append(x >= 0x20 && x < 0x7f ? (char)x : '.'); }
        return s.ToString();
    }
    static bool Printable(ulong a)
    {
        byte[] b = Read(a, 16);
        if (b == null || b[0] < 0x20 || b[0] > 0x7e) return false;
        int ok = 0;
        for (int i = 0; i < b.Length; i++)
        {
            if (b[i] == 0) return ok >= 3;
            if (b[i] >= 0x20 && b[i] < 0x7f) ok++; else break;
        }
        return ok >= 3;
    }
    public static string Pos(ulong a)
    {
        byte[] b = Read(a, 12);
        return b == null ? "<x>" : BitConverter.ToSingle(b,0).ToString("0.0") + "," + BitConverter.ToSingle(b,4).ToString("0.0") + "," + BitConverter.ToSingle(b,8).ToString("0.0");
    }

    static string Vad(ulong a)
    {
        MBI mb = new MBI(); int r2;
        int st = NtQueryVirtualMemory(H, IP(a), 0, ref mb, Marshal.SizeOf(typeof(MBI)), out r2);
        if (st != 0) return "st=0x" + unchecked((uint)st).ToString("x8");
        return "base=0x" + mb.BaseAddress.ToInt64().ToString("x") + " alloc=0x" + mb.AllocationBase.ToInt64().ToString("x")
             + " sz=0x" + mb.RegionSize.ToInt64().ToString("x") + " st=0x" + mb.State.ToString("x")
             + " p=0x" + mb.Protect.ToString("x") + " t=0x" + mb.Type.ToString("x") + " ap=0x" + mb.AllocationProtect.ToString("x");
    }

    public static string SetDebug()
    {
        IntPtr tok;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return "OpenProcessToken err=" + Marshal.GetLastWin32Error();
        long luid;
        if (!LookupPrivilegeValue(null, "SeDebugPrivilege", out luid)) return "LookupPrivilegeValue err=" + Marshal.GetLastWin32Error();
        TP tp = new TP(); tp.Count = 1; tp.Luid = luid; tp.Attr = 2;
        if (!AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return "Adjust err=" + Marshal.GetLastWin32Error();
        int e = Marshal.GetLastWin32Error();
        return e == 0 ? "ok" : "warn err=" + e;
    }

    public static string Open(int pid)
    {
        // privileged first: 0x10 alone cannot drive NtQueryInformationProcess or
        // NtQueryVirtualMemory (both need 0x400), which the peb and va-scan routes need.
        uint[] accs = new uint[] { 0x1F0FFF, 0x438, 0x410, 0x10 };
        StringBuilder s = new StringBuilder();
        foreach (uint a in accs)
        {
            IntPtr h = OpenProcess(a, false, pid);
            if (h == IntPtr.Zero) { s.Append("0x" + a.ToString("x") + ":err=" + Marshal.GetLastWin32Error() + " "); continue; }
            if (H != IntPtr.Zero) CloseHandle(H);
            H = h; Acc = a;
            s.Append("0x" + a.ToString("x") + ":ok");
            return s.ToString();
        }
        return s.ToString();
    }
    public static void Close() { if (H != IntPtr.Zero) CloseHandle(H); H = IntPtr.Zero; }

    public static bool QueryOk;

    static bool Reopen(uint mask)
    {
        IntPtr h = OpenProcess(mask, false, PidOf);
        if (h == IntPtr.Zero) return false;
        if (H != IntPtr.Zero) CloseHandle(H);
        H = h; Acc = mask;
        return true;
    }

    // escalation only: reopen at the lowest mask that carries PROCESS_QUERY_INFORMATION
    // and re-test the query. never downgrades below the current mask.
    static bool EnsureQuery()
    {
        PBI pb = new PBI(); int r;
        if (NtQueryInformationProcess(H, 0, ref pb, Marshal.SizeOf(typeof(PBI)), out r) == 0) { QueryOk = true; return true; }
        foreach (uint m in new uint[] { 0x410, 0x438, 0x1F0FFF })
        {
            if (m <= Acc) continue;
            if (!Reopen(m)) continue;
            if (NtQueryInformationProcess(H, 0, ref pb, Marshal.SizeOf(typeof(PBI)), out r) == 0) { QueryOk = true; return true; }
        }
        QueryOk = false;
        return false;
    }
    static string BaseViaPeb()
    {
        PBI pbi = new PBI(); int ret;
        int st = NtQueryInformationProcess(H, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret);
        if (st != 0) return "ntqip st=0x" + unchecked((uint)st).ToString("x8");
        if (pbi.PebBaseAddress == IntPtr.Zero) return "peb null";
        ulong peb = (ulong)pbi.PebBaseAddress.ToInt64();
        // the peb read is itself the reader proof: a working engine here yields the base,
        // so this must not depend on a prior ksud-validated Mode.
        StringBuilder d = new StringBuilder();
        foreach (string m in WIN)
        {
            byte[] b = ReadM(m, peb + 0x10, 8);
            if (b == null) { d.Append(m + ":" + Fmt(LastReadErr) + " "); continue; }
            ulong cand = BitConverter.ToUInt64(b, 0);
            if (cand == 0) { d.Append(m + ":zero "); continue; }
            byte[] mz = ReadM(m, cand, 2);
            if (mz == null) { d.Append(m + ":base0x" + cand.ToString("x") + Fmt(LastReadErr) + " "); continue; }
            if (mz[0] != 0x4d || mz[1] != 0x5a) { d.Append(m + ":noMZ@0x" + cand.ToString("x") + " "); continue; }
            Mode = m; Base = cand; ImgEnd = cand + 0xE100000UL;
            return "ok(peb) via " + m + " base=0x" + cand.ToString("x");
        }
        return "peb@0x" + peb.ToString("x") + " unreadable [" + d.ToString().TrimEnd() + "]";
    }

    static string MapName(ulong a)
    {
        byte[] buf = new byte[0x400]; int r;
        int st = NtQueryVirtualMemoryName(H, IP(a), 2, buf, buf.Length, out r);
        if (st != 0) return "";
        int len = BitConverter.ToUInt16(buf, 0);
        if (len <= 0 || len > 0x400 - 16) return "";
        return Encoding.Unicode.GetString(buf, 16, len);
    }

    // read-free base route: MEM_IMAGE regions plus their mapped file name come straight
    // from the vad, so this works even when every read syscall is refused.
    static string BaseViaImageVad(out string dbg)
    {
        StringBuilder d = new StringBuilder();
        ulong a = 0x10000UL, best = 0; int imgs = 0, regions = 0;
        while (a < 0x7FFFFFFEFFFFUL)
        {
            MBI mb = new MBI(); int ret;
            int st = NtQueryVirtualMemory(H, IP(a), 0, ref mb, Marshal.SizeOf(typeof(MBI)), out ret);
            if (st != 0) { d.Append("q st=0x" + unchecked((uint)st).ToString("x8") + "@0x" + a.ToString("x")); break; }
            ulong sz = (ulong)mb.RegionSize.ToInt64();
            if (sz == 0) break;
            regions++;
            if (mb.State == 0x1000 && mb.Type == 0x1000000)
            {
                imgs++;
                string nm = MapName(a);
                if (nm.EndsWith("r5apex_dx12.exe", StringComparison.OrdinalIgnoreCase)
                 || nm.EndsWith("r5apex.exe", StringComparison.OrdinalIgnoreCase))
                {
                    ulong ab = (ulong)mb.AllocationBase.ToInt64();
                    if (ab != 0 && (best == 0 || ab < best)) best = ab;
                }
            }
            a += sz;
        }
        dbg = "regions=" + regions + " img_regions=" + imgs;
        if (best == 0) return "image-vad no match [" + d.ToString() + "]";
        Base = best; ImgEnd = best + 0xE100000UL;
        return "ok(image-vad) base=0x" + best.ToString("x");
    }

    static string BaseViaVirtualScan()
    {
        ulong a = 0x10000UL, best = 0, bestSz = 0;
        int regions = 0, imgs = 0;
        while (a < 0x7FFFFFFEFFFFUL)
        {
            MBI mb = new MBI(); int ret;
            int st = NtQueryVirtualMemory(H, IP(a), 0, ref mb, Marshal.SizeOf(typeof(MBI)), out ret);
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
                    if (lf > 0 && lf < 0x3c0 && h[lf] == 0x50 && h[lf+1] == 0x45 && h[lf+2] == 0 && h[lf+3] == 0)
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
        Base = best; ImgEnd = best + bestSz;
        return "ok(va-scan) base=0x" + best.ToString("x") + " size=0x" + bestSz.ToString("x") + " regions=" + regions;
    }

    static string BaseViaPsapi()
    {
        IntPtr[] mods = new IntPtr[512]; int need;
        if (!EnumProcessModulesEx(H, mods, mods.Length * IntPtr.Size, out need, 3))
            return "enum err=" + Marshal.GetLastWin32Error();
        MODINFO mi;
        if (!GetModuleInformation(H, mods[0], out mi, Marshal.SizeOf(typeof(MODINFO))))
            return "gmi err=" + Marshal.GetLastWin32Error();
        Base = (ulong)mi.Base.ToInt64();
        ImgEnd = Base + 0xE100000UL;
        return "ok(psapi) base=0x" + Base.ToString("x") + " size=0x" + ((ulong)mi.Size.ToInt64()).ToString("x");
    }

    static string BaseViaToolhelp()
    {
        IntPtr snap = CreateToolhelp32Snapshot(0x08 | 0x10, PidOf);
        if (snap == new IntPtr(-1)) return "snapshot err=" + Marshal.GetLastWin32Error();
        MODENT me = new MODENT();
        me.dwSize = (uint)Marshal.SizeOf(typeof(MODENT));
        try
        {
            if (!Module32FirstW(snap, ref me)) return "mod32first err=" + Marshal.GetLastWin32Error();
            do
            {
                if (string.Equals(me.szModule, "r5apex_dx12.exe", StringComparison.OrdinalIgnoreCase)
                 || string.Equals(me.szModule, "r5apex.exe", StringComparison.OrdinalIgnoreCase))
                {
                    Base = (ulong)me.modBaseAddr.ToInt64();
                    ImgEnd = Base + me.modBaseSize;
                    return "ok(toolhelp) base=0x" + Base.ToString("x") + " size=0x" + me.modBaseSize.ToString("x");
                }
            } while (Module32NextW(snap, ref me));
            return "no matching module";
        }
        finally { CloseHandle(snap); }
    }

    public static int PidOf;

    public static string GetBase()
    {
        List<string> why = new List<string>();
        string vs = "";
        if (QueryOk) { string pb = BaseViaPeb(); if (pb.StartsWith("ok")) return pb; why.Add(pb); }
        else why.Add("peb skipped (no query access)");
        if (QueryOk)
        {
            string dbg;
            string iv = BaseViaImageVad(out dbg);
            if (iv.StartsWith("ok")) return iv + " [after: " + string.Join("; ", why.ToArray()) + "]";
            why.Add(iv + " (" + dbg + ")");
        }
        else why.Add("image-vad skipped (no query access)");
        vs = BaseViaVirtualScan();
        if (vs.StartsWith("ok")) return vs + " [after: " + string.Join("; ", why.ToArray()) + "]";
        why.Add(vs);
        string ps = BaseViaPsapi();
        if (ps.StartsWith("ok")) return ps + " [after: " + string.Join("; ", why.ToArray()) + "]";
        why.Add(ps);
        string th = BaseViaToolhelp();
        if (th.StartsWith("ok")) return th + " [after: " + string.Join("; ", why.ToArray()) + "]";
        why.Add(th);
        return string.Join("; ", why.ToArray());
    }

    public static bool SigOk(ulong e)
    {
        int hp = I32(e + 0x330);
        if (hp < 1 || hp > 250) return false;
        int team = I32(e + 0x340);
        if (team < 0 || team > 30) return false;
        ulong sp = Q(e + 0x478);
        return sp != 0 && Printable(sp);
    }
    static bool EntAt(ulong slot, out ulong ent)
    {
        ent = Q(slot);
        return ent != 0 && (ent & 0xFUL) == 0 && SigOk(ent);
    }
    public static string Pipeline(int pid, bool full)
    {
        PidOf = pid;
        StringBuilder o = new StringBuilder();
        H = IntPtr.Zero; Base = 0; ImgEnd = 0; Mode = ""; Acc = 0; LastReadErr = 0;
        DateTime t0 = DateTime.UtcNow;

        o.AppendLine("== privilege ==");
        o.AppendLine("SetDebug: " + SetDebug());
        o.AppendLine("== open ==");
        o.AppendLine("masks: " + Open(pid));
        if (H == IntPtr.Zero) { o.AppendLine("PIPELINE=BLOCKED block=open"); return o.ToString(); }
        o.AppendLine("query: " + (EnsureQuery() ? "ok mask=0x" + Acc.ToString("x") : "FAIL gates peb+va-scan"));
        byte[] prot = new byte[8]; int pr;
        int pst = NtQueryInformationProcessB(H, 21, prot, prot.Length, out pr);
        o.AppendLine("protection: " + (pst == 0 ? "type=" + prot[0] + " audit=" + prot[1] + " signer=0x" + prot[2].ToString("x2") : "st=0x" + unchecked((uint)pst).ToString("x8")));
        byte[] ipb = new byte[0x400]; int ri;
        if (NtQueryInformationProcessB(H, 27, ipb, ipb.Length, out ri) == 0)
        {
            int ilen = BitConverter.ToUInt16(ipb, 0);
            if (ilen > 0 && ilen <= 0x400 - 16) o.AppendLine("image: " + Encoding.Unicode.GetString(ipb, 16, ilen));
        }

        o.AppendLine("== shapes @0x7FFE0320 n=4 ==");
        List<string> good = new List<string>();
        foreach (string m in MODES)
        {
            byte[] b = ReadM(m, 0x7FFE0320UL, 4);
            o.AppendLine("  " + m + "=" + (b != null ? "ok v=" + BitConverter.ToUInt32(b, 0).ToString("x8") + (BitConverter.ToUInt32(b, 0) == 0 ? " ZERO" : "") : Fmt(LastReadErr)));
            if (b != null) good.Add(m);
        }
        o.AppendLine("readers_ok=" + good.Count + "/" + MODES.Length);
        Mode = "";
        foreach (string m in WIN) if (good.Contains(m)) { Mode = m; break; }

        o.AppendLine("== base ==");
        o.AppendLine("route: " + GetBase());
        if (Base == 0) { o.AppendLine("PIPELINE=BLOCKED block=base"); return o.ToString(); }

        string win = "";
        List<string> order = new List<string>();
        if (good.Count == 0)
        {
            o.AppendLine("== read matrix @base (every reader failed at ksud) ==");
            List<string> rescue = new List<string>();
            foreach (uint mk in new uint[] { 0x10, 0x1010, 0x410, 0x438, 0x1F0FFF })
            {
                if (!Reopen(mk)) { o.AppendLine("  mask 0x" + mk.ToString("x") + ": open err=" + Marshal.GetLastWin32Error()); continue; }
                StringBuilder ln = new StringBuilder("  mask 0x" + mk.ToString("x") + ":");
                foreach (string eng in new string[] { "rpm", "nt", "ntex" })
                {
                    foreach (int sz in new int[] { 2, 8, 0x1000 })
                    {
                        byte[] bb = new byte[sz];
                        bool ok = Raw(eng, Base, bb, sz);
                        ln.Append(" " + eng + "/" + sz.ToString("x") + "=" + (ok ? "ok" + BitConverter.ToString(bb, 0, 2) : Fmt(LastReadErr)));
                        if (ok && !rescue.Contains(eng + "_exact")) rescue.Add(eng + "_exact");
                    }
                }
                o.AppendLine(ln.ToString());
            }
            foreach (string m in rescue) order.Add(m);
        }
        if (Mode != "" && !good.Contains(Mode)) order.Add(Mode);
        foreach (string m in WIN) if (good.Contains(m) && !order.Contains(m)) order.Add(m);
        foreach (string m in good) if (!order.Contains(m)) order.Add(m);
        string mzOnly = "";
        foreach (string m in order)
        {
            byte[] mz = ReadM(m, Base, 2);
            if (mz == null || mz[0] != 0x4d || mz[1] != 0x5a) { o.AppendLine("  verify " + m + ": mz " + Fmt(LastReadErr)); continue; }
            byte[] pg = ReadM(m, Base + 0x1000, 0x1000);
            o.AppendLine("  verify " + m + ": mz=ok page4k=" + (pg != null ? "ok" : Fmt(LastReadErr)));
            if (pg == null) { if (mzOnly == "") mzOnly = m; continue; }
            win = m; break;
        }
        if (win == "" && mzOnly != "") { win = mzOnly; o.AppendLine("  warning: no reader did a 4k read, using " + mzOnly); }
        if (win == "")
        {
            o.AppendLine("reader_verify: FAIL on MZ @0x" + Base.ToString("x"));
            o.AppendLine("  vad@base: " + Vad(Base));
            o.AppendLine("  vad@ksud: " + Vad(0x7FFE0000UL));
            PBI pb2 = new PBI(); int rr;
            if (NtQueryInformationProcess(H, 0, ref pb2, Marshal.SizeOf(typeof(PBI)), out rr) == 0 && pb2.PebBaseAddress != IntPtr.Zero)
                o.AppendLine("  vad@peb:  " + Vad((ulong)pb2.PebBaseAddress.ToInt64()));
            o.AppendLine("PIPELINE=BLOCKED block=reader");
            o.AppendLine("hint: every read refused while vad/query work => target filter (eaac), not our handle");
            return o.ToString();
        }
        Mode = win;
        o.AppendLine("reader_verify: first2=4d5a via " + Mode + " acc=0x" + Acc.ToString("x"));
        o.AppendLine("base=0x" + Base.ToString("x") + " imgsize=0x" + (ImgEnd - Base).ToString("x"));

        o.AppendLine("== scan " + (full ? "FULL-VSIZE" : "FILE-BACKED") + " ==");
        Scan(o, full, t0);
        return o.ToString();
    }
    static void Scan(StringBuilder o, bool full, DateTime t0)
    {
        ulong start = Base + DATA_RVA;
        ulong end = start + (full ? DATA_VSIZE : DATA_RAW);
        Dictionary<ulong, ulong> map = new Dictionary<ulong, ulong>();
        List<ulong> ints = new List<ulong>();
        int unread = 0, batches = 0;

        for (ulong a = start; a < end; a += (ulong)BATCH)
        {
            int len = (int)Math.Min((ulong)BATCH, end - a);
            byte[] buf = Read(a, len);
            batches++;
            if (buf == null) { unread++; continue; }
            for (int off = 0; off + 8 <= len; off += 8)
            {
                ulong v = BitConverter.ToUInt64(buf, off);
                if (v >= 0x10000UL && v < 0x0000800000000000UL && (v & 7UL) == 0 && (v < Base || v >= ImgEnd))
                {
                    if (map.Count < CAP && !map.ContainsKey(v)) map[v] = a + (ulong)off;
                }
                else
                {
                    int iv = BitConverter.ToInt32(buf, off);
                    if (iv > 0 && iv <= 0x4000 && ints.Count < 4000000) ints.Add(a + (ulong)off);
                }
            }
        }
        o.AppendLine("scan: batches=" + batches + " unreadable=" + unread + " ptr_cand=" + map.Count
            + " int_cand=" + ints.Count + " took=" + (DateTime.UtcNow - t0).TotalSeconds.ToString("0.0") + "s");
        if (unread == batches) { o.AppendLine("PIPELINE=BLOCKED block=scan-all-unreadable"); return; }

        List<KeyValuePair<ulong, ulong>> hit = new List<KeyValuePair<ulong, ulong>>();
        foreach (KeyValuePair<ulong, ulong> kv in map) if (SigOk(kv.Key)) hit.Add(kv);
        o.AppendLine("validate: passing_targets=" + hit.Count);
        if (hit.Count == 0) { o.AppendLine("RESULT=NO_SIGNATURE_HITS"); o.AppendLine("PIPELINE=OK"); return; }

        List<ulong[]> runs = new List<ulong[]>();
        int scanMax = Math.Min(hit.Count, 1200);
        for (int i = 0; i < scanMax; i++)
        {
            ulong t = hit[i].Key;
            int back = 0; ulong e2;
            while (back < 512 && EntAt(t - (ulong)(8 * (back + 1)), out e2)) back++;
            int fwd = 0;
            while (fwd < 512 && EntAt(t + (ulong)(8 * (fwd + 1)), out e2)) fwd++;
            int len2 = back + fwd + 1;
            if (len2 >= 3) runs.Add(new ulong[] { t - (ulong)(8 * back), (ulong)len2 });
        }
        runs.Sort(delegate (ulong[] x, ulong[] y) { return y[1].CompareTo(x[1]); });
        o.AppendLine("arrays_found=" + runs.Count);
        for (int i = 0; i < Math.Min(5, runs.Count); i++)
            o.AppendLine("  arr[" + i + "] base=0x" + runs[i][0].ToString("x") + " run=" + runs[i][1]);

        if (runs.Count == 0)
        {
            o.AppendLine("singletons (sparse list):");
            for (int i = 0; i < Math.Min(hit.Count, 24); i++)
            {
                ulong t = hit[i].Key;
                o.AppendLine("  rva=0x" + (hit[i].Value - Base).ToString("x") + " ent=0x" + t.ToString("x")
                    + " hp=" + I32(t + 0x330) + " team=" + I32(t + 0x340)
                    + " sig=\"" + Ascii(Q(t + 0x478), 20) + "\" pos=" + Pos(t + 0x170));
            }
            o.AppendLine("RESULT=SINGLETONS_ONLY");
            o.AppendLine("PIPELINE=OK");
            return;
        }
        ulong best = runs[0][0];
        int bestLen = (int)runs[0][1];
        o.AppendLine("== chosen array base=0x" + best.ToString("x") + " len=" + bestLen);
        foreach (ulong probe in new ulong[] { best, best - 8, best + 8, best + 16 })
        {
            ulong slot;
            if (map.TryGetValue(probe, out slot)) o.AppendLine("  global_rva=0x" + (slot - Base).ToString("x") + " -> 0x" + probe.ToString("x"));
        }
        o.AppendLine("== array contents ==");
        for (int i = 0; i < Math.Min(bestLen, 32); i++)
        {
            ulong v = Q(best + (ulong)(8 * i));
            if (v == 0) { o.AppendLine("  [" + i + "] 0"); continue; }
            if (!SigOk(v)) { o.AppendLine("  [" + i + "] 0x" + v.ToString("x") + " (no sig)"); continue; }
            o.AppendLine("  [" + i + "] ent=0x" + v.ToString("x") + " hp=" + I32(v + 0x330) + " team=" + I32(v + 0x340)
                + " shield=" + I32(v + 0x18C) + " vis=0x" + I32(v + 0x338).ToString("x")
                + " sig=\"" + Ascii(Q(v + 0x478), 20) + "\" pos=" + Pos(v + 0x170));
        }
        o.AppendLine("== local handle search ==");
        HashSet<ulong> seen = new HashSet<ulong>();
        foreach (ulong probe in new ulong[] { best, best - 8, best + 8, best + 16 })
        {
            ulong slot;
            if (!map.TryGetValue(probe, out slot)) continue;
            ulong lo = slot > 0x2000 ? slot - 0x2000 : slot;
            for (ulong s = (lo & ~3UL); s < slot + 0x2000; s += 4)
            {
                if (!seen.Add(s)) continue;
                int iv = I32(s);
                if (iv < 1 || iv > 0x4000) continue;
                ulong idx = (ulong)(iv - 1);
                if (idx >= (ulong)bestLen) continue;
                ulong cand = Q(best + idx * 8);
                if (cand == 0 || !SigOk(cand)) continue;
                o.AppendLine("  handle_rva=0x" + (s - Base).ToString("x") + " idx=" + idx + " hp=" + I32(cand + 0x330)
                    + " team=" + I32(cand + 0x340) + " sig=\"" + Ascii(Q(cand + 0x478), 20) + "\"");
            }
        }
        o.AppendLine("RESULT=DONE");
        o.AppendLine("PIPELINE=OK");
    }
}
'@
try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
} catch {
    ("compile FAILED: " + $_.Exception.Message) | Out-File -LiteralPath $rep -Encoding ascii
    ("compile FAILED: " + $_.Exception.Message) | Out-File -LiteralPath $sta -Encoding ascii
    exit 1
}

function Get-GamePid {
    $p = Get-Process -Name 'r5apex_dx12', 'r5apex' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return [int]$p.Id }
    return 0
}

$run = 0
while ($true) {
    $run++
    $stamp = Get-Date -Format s
    $gpid = if ($PidOverride) { $PidOverride } else { Get-GamePid }
    if (-not $gpid -or -not (Get-Process -Id $gpid -ErrorAction SilentlyContinue)) {
        "t=$stamp state=waiting_no_game" | Out-File -LiteralPath $sta -Encoding ascii
        "[$stamp] WAITING - launch Apex and join Firing Range" | Out-File -LiteralPath $rep -Encoding ascii
        Start-Sleep -Seconds 3
        continue
    }

    "t=$stamp state=running pid=$gpid run=$run" | Out-File -LiteralPath $sta -Encoding ascii
    $hdr = "run=$run t=$stamp pid=$gpid admin=$adm full=$($Full.IsPresent)`r`npriv: $dbgPriv"
    try { $body = [R17]::Pipeline($gpid, $Full.IsPresent) }
    catch { $body = "EXCEPTION: " + $_.Exception.Message + "`nPIPELINE=BLOCKED block=exception" }
    $txt = $hdr + "`r`n" + $body
    $txt | Out-File -LiteralPath $rep -Encoding ascii
    $txt | Add-Content -LiteralPath $log -Encoding ascii
    [R17]::Close()

    $verdict = @($body -split "`n" | Where-Object { $_ -like 'PIPELINE=*' })[-1]
    "t=$(Get-Date -Format s) state=done run=$run $verdict" | Out-File -LiteralPath $sta -Encoding ascii

    if ($Once) { break }
    if ($PidOverride) { Start-Sleep -Seconds 15; continue }
    while ($true) {
        Start-Sleep -Seconds $IntervalSec
        if (-not (Get-Process -Id $gpid -ErrorAction SilentlyContinue)) { break }
        $now = Get-GamePid
        if ($now -and $now -ne $gpid) { break }
    }
}
"t=$(Get-Date -Format s) state=exit" | Out-File -LiteralPath $sta -Encoding ascii







