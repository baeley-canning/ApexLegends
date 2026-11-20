param([switch]$Full)

# 64-bit guard: from a WOW64 caller psapi truncates module bases to 32 bits and
# LIST_MODULES_ALL fails 87, so re-exec under the real 64-bit host.
if (-not [Environment]::Is64BitProcess) {
    $p64 = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $p64)) { $p64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Full) { $a += '-Full' }
    & $p64 @a
    exit
}

# h414 - locate the real globals by content in .data (no driver, no DTB)
# Default covers .data's file-backed extent (rawsize 0xD00800, 13.0 MB) - every
# initialised slot lives there; the other 166 MB of vsize is zero-fill. -Full scans it.
# A target is accepted only on a 3-field AND: int32 1..250 @0x330, int32 0..30 @0x340,
# ptr @0x478 -> printable ascii.
$ErrorActionPreference = 'Stop'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h414_out.txt'

$src = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class S
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
    public static ulong ImgEnd;
    public static int Pid;

    const ulong DATA_RVA   = 0x334C000;
    const ulong DATA_RAW   = 0xD00800;    // file-backed extent - holds every initialised slot
    const ulong DATA_VSIZE = 0xAB23AAC;   // full virtual size; rest is zero-fill
    const int   BATCH      = 0x10000;
    const int   CAP        = 3000000;

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
        Pid = pid;
        H = OpenProcess(0x0410, false, pid);
        if (H != IntPtr.Zero) return "ok (Q_INFO|VM_READ)";
        string ev = "0x0410 failed err=" + Marshal.GetLastWin32Error();
        H = OpenProcess(0x1000, false, pid);
        return H == IntPtr.Zero ? ev + "; 0x1000 failed err=" + Marshal.GetLastWin32Error() : ev + "; limited-only (psapi will fail 87)";
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
                    ImgEnd = Base + me.modBaseSize;
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
        ImgEnd = Base + 0xDFB8000UL;
        return "ok(peb) base=0x" + Base.ToString("x");
    }

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
        ImgEnd = best + bestSz;
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
            if (!GetModuleInformation(H, mods[0], out mi, Marshal.SizeOf(typeof(MODINFO))))
            {
                why = "GMI err=" + Marshal.GetLastWin32Error();
            }
            else
            {
                Base = (ulong)mi.Base.ToInt64();
                ImgEnd = Base + 0xDFB8000UL;
                return "ok base=0x" + Base.ToString("x") + " size=0x" + ((ulong)mi.Size.ToInt64()).ToString("x");
            }
        }
        else
        {
            int e1 = Marshal.GetLastWin32Error();
            why += "; Enum err=" + e1;
            if (e1 == 87)
            {
                int need2;
                if (EnumProcessModulesEx(H, mods, mods.Length * IntPtr.Size, out need2, 2))
                {
                    MODINFO mi2;
                    if (GetModuleInformation(H, mods[0], out mi2, Marshal.SizeOf(typeof(MODINFO))))
                    {
                        Base = (ulong)mi2.Base.ToInt64();
                        ImgEnd = Base + 0xDFB8000UL;
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

    static bool Printable(ulong a)
    {
        byte[] b = Read(a, 16);
        if (b == null || b[0] < 0x20 || b[0] > 0x7e) return false;
        int ok = 0;
        for (int i = 0; i < b.Length; i++) { if (b[i] == 0) return ok >= 3; if (b[i] >= 0x20 && b[i] < 0x7f) ok++; else break; }
        return ok >= 3;
    }

    public static string Ascii(ulong a, int n)
    {
        byte[] b = Read(a, n);
        if (b == null) return "";
        StringBuilder s = new StringBuilder();
        foreach (byte x in b) { if (x == 0) break; s.Append(x >= 0x20 && x < 0x7f ? (char)x : '.'); }
        return s.ToString();
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

    public static string Run(int pid, bool full)
    {
        StringBuilder o = new StringBuilder();
        o.AppendLine("h414 pid=" + pid + " mode=" + (full ? "FULL-VSIZE" : "FILE-BACKED"));
        o.AppendLine("SetDebug: " + SetDebug());
        o.AppendLine("Open: " + Open(pid));
        if (H == IntPtr.Zero) return o.ToString();
        string b = GetBase();
        o.AppendLine("Base: " + b);
        if (Base == 0) return o.ToString();

        ulong start = Base + DATA_RVA;
        ulong end = start + (full ? DATA_VSIZE : DATA_RAW);
        Dictionary<ulong, ulong> map = new Dictionary<ulong, ulong>();
        List<ulong> ints = new List<ulong>();
        int unread = 0, batches = 0;
        DateTime t0 = DateTime.UtcNow;

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
        double secs = (DateTime.UtcNow - t0).TotalSeconds;
        o.AppendLine("scan: batches=" + batches + " unreadable=" + unread + " ptr_candidates=" + map.Count
            + " int_candidates=" + ints.Count + " took=" + secs.ToString("0.0") + "s");

        List<KeyValuePair<ulong, ulong>> hit = new List<KeyValuePair<ulong, ulong>>();
        t0 = DateTime.UtcNow;
        foreach (KeyValuePair<ulong, ulong> kv in map)
            if (SigOk(kv.Key)) hit.Add(kv);
        o.AppendLine("validate: passing_targets=" + hit.Count + " took=" + (DateTime.UtcNow - t0).TotalSeconds.ToString("0.0") + "s");
        if (hit.Count == 0) { o.AppendLine("RESULT=NO_SIGNATURE_HITS"); return o.ToString(); }

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
            o.AppendLine("no run >=3; dumping passing singletons (sparse list, e.g. Firing Range)");
            int n0 = Math.Min(hit.Count, 40);
            for (int i = 0; i < n0; i++)
            {
                ulong t = hit[i].Key;
                byte[] x0 = Read(t + 0x170, 12);
                string p0 = x0 == null ? "<x>" : BitConverter.ToSingle(x0,0).ToString("0.0") + "," + BitConverter.ToSingle(x0,4).ToString("0.0") + "," + BitConverter.ToSingle(x0,8).ToString("0.0");
                o.AppendLine("  rva=0x" + (hit[i].Value - Base).ToString("x") + " ent=0x" + t.ToString("x")
                    + " hp=" + I32(t + 0x330) + " team=" + I32(t + 0x340)
                    + " shield=" + I32(t + 0x18C) + " sig=\"" + Ascii(Q(t + 0x478), 20) + "\" pos=" + p0);
            }
            o.AppendLine("RESULT=SINGLETONS_ONLY");
            return o.ToString();
        }

        ulong best = runs[0][0];
        int bestLen = (int)runs[0][1];
        o.AppendLine("== chosen array base=0x" + best.ToString("x") + " len=" + bestLen);
        foreach (ulong probe in new ulong[] { best, best - 8, best + 8, best + 16 })
        {
            ulong slot;
            if (map.TryGetValue(probe, out slot))
                o.AppendLine("  global_candidate rva=0x" + (slot - Base).ToString("x") + " -> 0x" + probe.ToString("x"));
        }

        o.AppendLine("== array contents ==");
        for (int i = 0; i < Math.Min(bestLen, 64); i++)
        {
            ulong v = Q(best + (ulong)(8 * i));
            if (v == 0) { o.AppendLine("  [" + i + "] 0"); continue; }
            if (!SigOk(v)) { o.AppendLine("  [" + i + "] 0x" + v.ToString("x") + " (no sig)"); continue; }
            byte[] xyz = Read(v + 0x170, 12);
            string pos = xyz == null ? "<x>" : BitConverter.ToSingle(xyz,0).ToString("0.0") + "," + BitConverter.ToSingle(xyz,4).ToString("0.0") + "," + BitConverter.ToSingle(xyz,8).ToString("0.0");
            o.AppendLine("  [" + i + "] ent=0x" + v.ToString("x") + " hp=" + I32(v + 0x330) + " team=" + I32(v + 0x340)
                + " shield=" + I32(v + 0x18C) + "/" + I32(v + 0x190)
                + " sig=\"" + Ascii(Q(v + 0x478), 20) + "\" pos=" + pos);
        }

        o.AppendLine("== local-handle search (globals cluster; +-0x2000 around global slots) ==");
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
                o.AppendLine("  handle_rva=0x" + (s - Base).ToString("x") + " idx=" + idx + " ent=0x" + cand.ToString("x")
                    + " hp=" + I32(cand + 0x330) + " team=" + I32(cand + 0x340)
                    + " sig=\"" + Ascii(Q(cand + 0x478), 20) + "\"");
            }
        }

        o.AppendLine("RESULT=DONE");
        return o.ToString();
    }
}
'@

try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
    $p = Get-Process -Name 'r5apex_dx12' -ErrorAction SilentlyContinue
    if (-not $p) {
        "RESULT=NO_GAME" | Out-File -FilePath $out -Encoding ascii
    } else {
        $gpid = [int]$p[0].Id
        ($("pid=$gpid started=$(Get-Date -Format s)`n") + [S]::Run($gpid, $Full.IsPresent)) | Out-File -FilePath $out -Encoding ascii
    }
    "rc=0" | Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h414_rc.txt' -Encoding ascii
    "WROTE $out"
} catch {
    "rc=1`n" + $_.Exception.Message | Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_h414_rc.txt' -Encoding ascii
    "ERROR: " + $_.Exception.Message
}
