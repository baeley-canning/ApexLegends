param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_inj3_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class I3
{
    static string OUT;
    static void W(string x) { System.IO.File.AppendAllText(OUT, x + "\r\n"); }

    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr w);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, IntPtr ss, IntPtr st, IntPtr par, uint fl, IntPtr tid);
    [DllImport("kernel32", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError=true)] static extern bool GetExitCodeThread(IntPtr h, out IntPtr code);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("kernel32", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr hp, int cls, byte[] buf, int len, out int ret);
    [DllImport("ntdll")] static extern int NtQueryVirtualMemory(IntPtr hp, IntPtr addr, int cls, byte[] buf, IntPtr len, out IntPtr ret);

    static int Hits(IntPtr h)
    {
        int hits = 0;
        ulong a = 0x10000;
        byte[] bi = new byte[48];
        byte[] nm = new byte[0x400];
        IntPtr rl;
        int g = 0;
        while (a < 0x7FFFFFFF0000UL && g++ < 20000)
        {
            if (NtQueryVirtualMemory(h, (IntPtr)(long)a, 0, bi, (IntPtr)48, out rl) != 0) { a += 0x10000; continue; }
            ulong b = BitConverter.ToUInt64(bi, 0);
            ulong s = BitConverter.ToUInt64(bi, 24);
            if (b < a) b = a;
            if (NtQueryVirtualMemory(h, (IntPtr)(long)b, 2, nm, (IntPtr)nm.Length, out rl) == 0)
            {
                int l = BitConverter.ToUInt16(nm, 0);
                if (l > 0 && l < 0x300 && Encoding.Unicode.GetString(nm, 16, l).IndexOf("avifil32", StringComparison.OrdinalIgnoreCase) >= 0) hits++;
            }
            if (s == 0) break;
            a = b + s;
        }
        return hits;
    }

    public static void Run(string outp)
    {
        OUT = outp;
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W("no target"); return; }
        int pid = ps[0].Id;
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) { W("open err=" + Marshal.GetLastWin32Error()); return; }
        W("pid=" + pid + " open ok");

        byte[] pbi = new byte[48];
        int rr;
        int qs = NtQueryInformationProcess(h, 0, pbi, 48, out rr);
        long peb = BitConverter.ToInt64(pbi, 8);
        W("peb st=0x" + qs.ToString("x8") + " peb=0x" + peb.ToString("x"));
        if (qs != 0 || peb == 0) return;

        long s1 = peb + 0xF00;
        long s2 = peb + 0xF80;
        IntPtr w;
        bool a1 = WriteProcessMemory(h, (IntPtr)s1, new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, (IntPtr)8, out w);
        W("wpm8 " + (a1 ? "ok n=" + w.ToInt64() : "err=" + Marshal.GetLastWin32Error()));
        byte[] path = Encoding.ASCII.GetBytes("C:\\Windows\\System32\\avifil32.dll\0");
        bool a2 = WriteProcessMemory(h, (IntPtr)s2, path, (IntPtr)path.Length, out w);
        W("wpm_path " + (a2 ? "ok n=" + w.ToInt64() : "err=" + Marshal.GetLastWin32Error()));

        int pre = Hits(h);
        W("pre_hits=" + pre);
        IntPtr ll = GetProcAddress(GetModuleHandle("kernel32"), "LoadLibraryA");
        IntPtr th = CreateRemoteThread(h, IntPtr.Zero, IntPtr.Zero, ll, (IntPtr)s2, 0, IntPtr.Zero);
        if (th == IntPtr.Zero) { W("crt err=" + Marshal.GetLastWin32Error()); }
        else
        {
            W("crt ok h=0x" + th.ToString("x"));
            WaitForSingleObject(th, 5000);
            IntPtr code;
            GetExitCodeThread(th, out code);
            W("exit=0x" + code.ToString("x"));
            CloseHandle(th);
        }
        System.Threading.Thread.Sleep(800);
        int post = Hits(h);
        W("post_hits=" + post + " verdict=" + (post > pre ? "INJECT_OK" : "INJECT_FAIL"));
    }
}
'@ -Language CSharp -ErrorAction Stop
    [I3]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
