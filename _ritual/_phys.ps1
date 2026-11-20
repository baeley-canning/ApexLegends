param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_phys_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class Phys
{
    static string OUT;
    static void W(string x) { System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32")] static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, uint acc, out IntPtr tok);
    [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
    [DllImport("advapi32", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TP newst, int len, IntPtr prev, IntPtr rl);
    [DllImport("ntdll")] static extern int NtOpenSection(out IntPtr h, uint acc, IntPtr oa);
    [DllImport("ntdll")] static extern int NtQuerySection(IntPtr h, int cls, byte[] buf, int len, out int ret);
    [DllImport("ntdll")] static extern int NtMapViewOfSection(IntPtr hs, IntPtr hp, out IntPtr ba, IntPtr zero, IntPtr cs, ref long off, out IntPtr vs, int inh, uint at, uint prot);
    [DllImport("ntdll")] static extern int NtUnmapViewOfSection(IntPtr hp, IntPtr ba);

    [StructLayout(LayoutKind.Sequential)] struct TP { public int Count; public long Luid; public int Attr; }

    static bool Priv()
    {
        IntPtr tok;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return false;
        long luid;
        if (!LookupPrivilegeValue(null, "SeLockMemoryPrivilege", out luid)) return false;
        TP t = new TP(); t.Count = 1; t.Luid = luid; t.Attr = 2;
        return AdjustTokenPrivileges(tok, false, ref t, 0, IntPtr.Zero, IntPtr.Zero);
    }

    static IntPtr Oa(string name, IntPtr nameBuf)
    {
        byte[] n = Encoding.Unicode.GetBytes(name);
        Marshal.WriteInt16(nameBuf, (short)n.Length);
        Marshal.WriteInt16(nameBuf, 2, (short)(n.Length + 2));
        IntPtr strBuf = Marshal.AllocHGlobal(n.Length + 2);
        Marshal.Copy(n, 0, strBuf, n.Length);
        Marshal.WriteInt16(strBuf, n.Length, 0);
        Marshal.WriteIntPtr(nameBuf, 8, strBuf);
        IntPtr oa = Marshal.AllocHGlobal(48);
        for (int i = 0; i < 48; i++) Marshal.WriteByte(oa, i, 0);
        Marshal.WriteInt32(oa, 0, 48);
        Marshal.WriteIntPtr(oa, 8, IntPtr.Zero);
        Marshal.WriteIntPtr(oa, 16, nameBuf);
        Marshal.WriteInt32(oa, 24, 0x40);
        return oa;
    }

    public static void Run(string outp)
    {
        OUT = outp;
        bool pv = Priv();
        W("lockmem_priv=" + pv + " lasterr=" + Marshal.GetLastWin32Error());
        IntPtr nb = Marshal.AllocHGlobal(16);
        IntPtr oa = Oa("\\Device\\PhysicalMemory", nb);
        IntPtr hs = IntPtr.Zero;
        foreach (uint m in new uint[] { 0x1u, 0x4u, 0x2u, 0x5u, 0x6u, 0xFu, 0u })
        {
            int s2 = NtOpenSection(out hs, m, oa);
            W("open acc=0x" + m.ToString("x") + " st=0x" + s2.ToString("x8"));
            if (s2 == 0) break;
        }
        if (hs == IntPtr.Zero) return;
        byte[] bi = new byte[24];
        int rl;
        int q = NtQuerySection(hs, 1, bi, 24, out rl);
        long size = BitConverter.ToInt64(bi, 8);
        W("querysection st=0x" + q.ToString("x8") + " size=0x" + size.ToString("x"));

        IntPtr cur = GetCurrentProcess();
        long off = 0;
        IntPtr view; IntPtr vs;
        int ms = NtMapViewOfSection(hs, cur, out view, IntPtr.Zero, IntPtr.Zero, ref off, out vs, 2, 0, 2);
        W("map st=0x" + ms.ToString("x8") + " view=0x" + view.ToString("x") + " vs=0x" + vs.ToString("x"));
        if (ms != 0) return;
        byte[] mbr = new byte[0x200];
        Marshal.Copy(view, mbr, 0, 0x200);
        W("mbr=" + mbr[0].ToString("x2") + mbr[1].ToString("x2") + " sig55aa=" + (mbr[0x1FE] == 0x55 && mbr[0x1FF] == 0xAA));
        NtUnmapViewOfSection(cur, view);
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Phys]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
