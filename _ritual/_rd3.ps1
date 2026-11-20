param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_rd3_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class Rd3
{
    static string OUT;
    static void W(string x) { System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
    [DllImport("ntdll")] static extern int NtReadVirtualMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr r);
    [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr hp, int cls, byte[] buf, int len, out int ret);

    static void Probe(int pid, string tag)
    {
        IntPtr h = OpenProcess(0x410, false, pid);
        if (h == IntPtr.Zero) { W(tag + " open err=" + Marshal.GetLastWin32Error()); return; }
        byte[] pbi = new byte[48];
        int rr;
        int q = NtQueryInformationProcess(h, 0, pbi, 48, out rr);
        long peb = BitConverter.ToInt64(pbi, 8);
        W(tag + " qip=0x" + q.ToString("x8") + " peb=0x" + peb.ToString("x"));
        if (peb == 0) return;
        IntPtr r;
        byte[] b = new byte[0x10];
        int st = NtReadVirtualMemory(h, (IntPtr)peb, b, (IntPtr)16, out r);
        W(tag + " ntrvm=0x" + st.ToString("x8") + " n=" + r.ToInt64() + " b0=0x" + b[0].ToString("x2"));
        bool ok = ReadProcessMemory(h, (IntPtr)peb, b, (IntPtr)16, out r);
        W(tag + " rpm=" + (ok ? "ok" : "err=" + Marshal.GetLastWin32Error()));
    }

    public static void Run(string outp)
    {
        OUT = outp;
        W("ps64=" + Environment.Is64BitProcess + " os64=" + Environment.Is64BitOperatingSystem);
        Process np = Process.Start("notepad.exe");
        System.Threading.Thread.Sleep(1200);
        Probe(np.Id, "notepad");
        try { np.Kill(); } catch { }
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W("no apex"); return; }
        Probe(ps[0].Id, "apex");
        W("apex_modules=" + ps[0].Modules.Count);
        W("apex_threads=" + ps[0].Threads.Count);
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Rd3]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
