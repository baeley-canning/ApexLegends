param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_rd_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class Rd
{
    static string OUT;
    static void W(string x) { System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
    [DllImport("ntdll")] static extern int NtQueryVirtualMemory(IntPtr hp, IntPtr addr, int cls, byte[] buf, IntPtr len, out IntPtr ret);

    public static void Run(string outp)
    {
        OUT = outp;
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W("no target"); return; }
        int pid = ps[0].Id;
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) { W("open err=" + Marshal.GetLastWin32Error()); return; }
        W("pid=" + pid + " open ok");

        byte[] bi = new byte[0x30];
        byte[] nm = new byte[0x400];
        IntPtr rl;
        ulong a = 0x10000;
        long baseAddr = 0;
        int g = 0;
        while (a < 0x7FFFFFFF0000UL && g++ < 40000 && baseAddr == 0)
        {
            if (NtQueryVirtualMemory(h, (IntPtr)(long)a, 0, bi, (IntPtr)0x30, out rl) != 0) { a += 0x10000; continue; }
            ulong b = BitConverter.ToUInt64(bi, 0);
            ulong s = BitConverter.ToUInt64(bi, 0x18);
            if (b < a) b = a;
            if ((BitConverter.ToUInt32(bi, 0x28) & 0x1000000) != 0 && (BitConverter.ToUInt32(bi, 0x20) & 0x1000) != 0)
            {
                if (NtQueryVirtualMemory(h, (IntPtr)(long)b, 2, nm, (IntPtr)nm.Length, out rl) == 0)
                {
                    int l = BitConverter.ToUInt16(nm, 0);
                    string n = l > 0 && l < 0x300 ? Encoding.Unicode.GetString(nm, 0x10, l) : "";
                    if (n.IndexOf("r5apex_dx12.exe", StringComparison.OrdinalIgnoreCase) >= 0) { baseAddr = (long)b; W("base=0x" + b.ToString("x") + " name=" + n); break; }
                }
            }
            if (s == 0) break;
            a = b + s;
        }
        if (baseAddr == 0) { W("base not found, scan=" + g); return; }

        foreach (int off in new int[] { 0 })
        {
            byte[] buf = new byte[0x400];
            bool ok = ReadProcessMemory(h, (IntPtr)(baseAddr + off), buf, (IntPtr)buf.Length, out rl);
            W("rpm off=0x" + off.ToString("x") + " " + (ok ? "ok n=" + rl.ToInt64() : "err=" + Marshal.GetLastWin32Error()));
            if (ok) W("mz=" + buf[0].ToString("x2") + buf[1].ToString("x2") + " pe_off=0x" + BitConverter.ToInt32(buf, 0x3C).ToString("x")
                + " e_lfanew_ok=" + (BitConverter.ToInt32(buf, 0x3C) > 0 && BitConverter.ToInt32(buf, 0x3C) < 0x3F0));
        }

        long t1 = baseAddr + 0x3B00000;
        byte[] b2 = new byte[0x100];
        bool ok2 = ReadProcessMemory(h, (IntPtr)t1, b2, (IntPtr)b2.Length, out rl);
        W("rpm_data 0x" + t1.ToString("x") + " " + (ok2 ? "ok first=" + b2[0].ToString("x2") : "err=" + Marshal.GetLastWin32Error()));
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Rd]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
