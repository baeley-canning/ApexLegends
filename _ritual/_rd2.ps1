param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_rd2_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class Rd2
{
    static string OUT;
    static void W(string x) { System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll")] static extern int NtReadVirtualMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
    [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr hp, int cls, byte[] buf, int len, out int ret);

    static void Try1(Process p, uint mask, string tag)
    {
        IntPtr h = OpenProcess(mask, false, p.Id);
        if (h == IntPtr.Zero) { W(tag + " mask=0x" + mask.ToString("x") + " OPEN=err" + Marshal.GetLastWin32Error()); return; }
        W(tag + " mask=0x" + mask.ToString("x") + " open=ok");
        IntPtr r;
        byte[] b = new byte[0x10];
        int[] addrs = new int[] { 0x3b8000 };
        foreach (int ad in addrs)
        {
            int st = NtReadVirtualMemory(h, (IntPtr)ad, b, (IntPtr)b.Length, out r);
            W("  peb 0x" + ad.ToString("x") + " st=0x" + st.ToString("x8") + " n=" + r.ToInt64());
        }
        byte[] pbi = new byte[48];
        int rr;
        int q = NtQueryInformationProcess(h, 0, pbi, 48, out rr);
        long peb = BitConverter.ToInt64(pbi, 8);
        W("  ntqip st=0x" + q.ToString("x8") + " peb=0x" + peb.ToString("x"));
        if (q == 0 && peb != 0)
        {
            int st2 = NtReadVirtualMemory(h, (IntPtr)peb, b, (IntPtr)b.Length, out r);
            W("  realpeb st=0x" + st2.ToString("x8") + " n=" + r.ToInt64());
        }
        CloseHandle(h);
    }

    public static void Run(string outp)
    {
        OUT = outp;
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W("no target"); return; }
        Process p = ps[0];
        W("pid=" + p.Id);
        foreach (uint m in new uint[] { 0x10u, 0x410u, 0x1F0FFFu, 0xFFFu, 0x1FFFFFu }) Try1(p, m, "t");
        try { W("mainmodule=0x" + p.MainModule.BaseAddress.ToString("x") + " name=" + p.MainModule.ModuleName); }
        catch (Exception e) { W("mainmodule EX " + e.Message); }
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Rd2]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
