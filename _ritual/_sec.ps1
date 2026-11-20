param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_sec_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Sec
{
    static string OUT;
    static void W(StringBuilder s, string x) { s.AppendLine(x); System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern bool DuplicateHandle(IntPtr hp, IntPtr src, IntPtr dst, out IntPtr tgt, uint acc, bool inh, uint opt);
    [DllImport("kernel32")] static extern IntPtr GetCurrentProcess();
    [DllImport("ntdll")] static extern int NtQuerySystemInformation(int cls, byte[] buf, int len, out int ret);
    [DllImport("ntdll")] static extern int NtQueryObject(IntPtr h, int cls, byte[] buf, int len, out int ret);
    [DllImport("ntdll")] static extern int NtMapViewOfSection(IntPtr hs, IntPtr hp, out IntPtr ba, IntPtr zero, IntPtr cs, IntPtr off, out IntPtr vs, int inh, uint at, uint prot);
    [DllImport("ntdll")] static extern int NtUnmapViewOfSection(IntPtr hp, IntPtr ba);

    const ulong DATA_RVA = 0x334C000UL;

    public static void Run(string outp)
    {
        StringBuilder o = new StringBuilder();
        OUT = outp;
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W(o, "no target"); return; }
        int pid = ps[0].Id;
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) { W(o, "open err=" + Marshal.GetLastWin32Error()); return; }
        W(o, "pid=" + pid + " open ok");

        int len = 1 << 20;
        byte[] buf = new byte[len];
        int rc = NtQuerySystemInformation(64, buf, len, out len);
        for (int i = 0; i < 6 && rc == unchecked((int)0xC0000004); i++)
        {
            buf = new byte[len <<= 1];
            rc = NtQuerySystemInformation(64, buf, buf.Length, out len);
        }
        if (rc != 0) { W(o, "nsysinfo st=0x" + rc.ToString("x8")); return; }
        ulong n = BitConverter.ToUInt64(buf, 0);
        W(o, "handles=" + n);

        IntPtr cur = GetCurrentProcess();
        int myPid = Process.GetCurrentProcess().Id;
        ulong apexObj = 0;
        for (ulong i = 0; i < n; i++)
        {
            int e = 16 + (int)i * 0x28;
            if (e + 0x28 > buf.Length) break;
            if (BitConverter.ToUInt64(buf, e + 8) != (ulong)myPid) continue;
            if (BitConverter.ToUInt64(buf, e + 16) != (ulong)h.ToInt64()) continue;
            apexObj = BitConverter.ToUInt64(buf, e);
        }
        int mine = 0;
        for (ulong i = 0; i < n; i++)
        {
            int e = 16 + (int)i * 0x28;
            if (e + 0x28 > buf.Length) break;
            if (BitConverter.ToUInt64(buf, e) != apexObj || apexObj == 0) continue;
            uint ga = BitConverter.ToUInt32(buf, e + 24);
            W(o, "our_handle hv=0x" + BitConverter.ToUInt64(buf, e + 16).ToString("x") + " ra=0x" + ga.ToString("x") + " type=" + BitConverter.ToUInt16(buf, e + 30));
            if (++mine > 6) break;
        }
        IntPtr hd = OpenProcess(0x40, false, pid);
        W(o, "dup_handle_open=" + (hd == IntPtr.Zero ? "err=" + Marshal.GetLastWin32Error() : "ok"));
        if (hd == IntPtr.Zero) hd = h;
        List<long> hitName = new List<long>();
        List<long> unnamed = new List<long>();
        int secs = 0, owners = 0, dfail = 0;
        int firstErr = 0;
        byte[] nb = new byte[0x400];
        for (ulong i = 0; i < n; i++)
        {
            int e = 16 + (int)i * 0x28;
            if (e + 0x28 > buf.Length) break;
            if (BitConverter.ToUInt64(buf, e + 8) != (ulong)pid) continue;
            owners++;
            IntPtr dup;
            if (!DuplicateHandle(hd, (IntPtr)(long)BitConverter.ToUInt64(buf, e + 16), cur, out dup, 0, false, 2))
            {
                if (firstErr == 0) firstErr = Marshal.GetLastWin32Error();
                dfail++;
                continue;
            }
            int rl;
            int qs = NtQueryObject(dup, 1, nb, nb.Length, out rl);
            int sl = 0;
            if (qs == 0) sl = BitConverter.ToUInt16(nb, 0);
            if (sl == 0) { if (unnamed.Count < 900) unnamed.Add(dup.ToInt64()); continue; }
            secs++;
            string nm = Encoding.Unicode.GetString(nb, 16, Math.Min(sl, 0x300));
            if (nm.IndexOf("r5apex_dx12", StringComparison.OrdinalIgnoreCase) >= 0) hitName.Add(dup.ToInt64());
            else if (unnamed.Count < 900) unnamed.Add(dup.ToInt64());
        }
        W(o, "owners=" + owners + " dup_fail=" + dfail + " first_err=" + firstErr + " named=" + hitName.Count + " unnamed=" + unnamed.Count + " secs=" + secs);


        List<long> order = new List<long>();
        order.AddRange(hitName);
        order.AddRange(unnamed);
        int tried = 0;
        foreach (long dh in order)
        {
            if (tried++ > 500) break;
            IntPtr view; IntPtr vs;
            int ms = NtMapViewOfSection((IntPtr)dh, cur, out view, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out vs, 1, 0, 2);
            if (ms != 0) continue;
            if (vs.ToInt64() < 0x1000) { NtUnmapViewOfSection(cur, view); continue; }
            byte[] hdr = new byte[0x1000];
            Marshal.Copy(view, hdr, 0, 0x1000);
            if (hdr[0] == 0x4D && hdr[1] == 0x5A)
            {
                int lf = BitConverter.ToInt32(hdr, 0x3C);
                if (lf > 0x40 && lf < 0x800 && hdr[lf] == 0x50 && hdr[lf + 1] == 0x45)
                {
                    uint soi = BitConverter.ToUInt32(hdr, lf + 0x50);
                    W(o, "MAP ok view=0x" + view.ToString("x") + " vsize=0x" + vs.ToString("x") + " sizeofimage=0x" + soi.ToString("x"));
                    if (soi > 0x1000000)
                    {
                        ulong da = (ulong)view.ToInt64() + DATA_RVA + 0x1000;
                        W(o, "data_probe=" + ((uint)Marshal.ReadInt32((IntPtr)(long)da)).ToString("x")
                            + "/" + ((uint)Marshal.ReadInt32((IntPtr)(long)(da + 8))).ToString("x"));
                        W(o, "VERDICT=SECTION_OK base=0x" + view.ToString("x"));
                        return;
                    }
                    NtUnmapViewOfSection(cur, view);
                    continue;
                }
            }
            NtUnmapViewOfSection(cur, view);
        }
        W(o, "VERDICT=SECTION_FAIL tried=" + tried);
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Sec]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
