param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_inj_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class Inj
{
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, IntPtr s, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr w);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, IntPtr ss, IntPtr st, IntPtr par, uint fl, IntPtr tid);
    [DllImport("kernel32", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError=true)] static extern bool GetExitCodeThread(IntPtr h, out IntPtr code);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("kernel32", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenThread(uint acc, bool inh, uint tid);
    [DllImport("kernel32")] static extern bool QueueUserAPC(IntPtr fn, IntPtr th, IntPtr data);
    [DllImport("ntdll")] static extern int NtQueryVirtualMemory(IntPtr hp, IntPtr addr, int cls, byte[] buf, IntPtr len, out IntPtr ret);

    const uint ALL = 0x1F0FFF;
    const string DLL = "C:\\Windows\\System32\\avifil32.dll";

    static int NameHits(IntPtr h)
    {
        int hits = 0;
        ulong a = 0x10000;
        byte[] bi = new byte[48];
        byte[] nm = new byte[0x400];
        IntPtr rl;
        int guard = 0;
        while (a < 0x7FFFFFFF0000UL && guard++ < 20000)
        {
            int st = NtQueryVirtualMemory(h, (IntPtr)(long)a, 0, bi, (IntPtr)48, out rl);
            if (st != 0) { a += 0x10000; continue; }
            ulong b = BitConverter.ToUInt64(bi, 0);
            ulong s = BitConverter.ToUInt64(bi, 24);
            if (b < a) b = a;
            if (NtQueryVirtualMemory(h, (IntPtr)(long)b, 2, nm, (IntPtr)nm.Length, out rl) == 0)
            {
                int len = BitConverter.ToUInt16(nm, 0);
                if (len > 0 && len < 0x300)
                {
                    string f = Encoding.Unicode.GetString(nm, 16, len);
                    if (f.IndexOf("avifil32", StringComparison.OrdinalIgnoreCase) >= 0) hits++;
                }
            }
            if (s == 0) break;
            a = b + s;
        }
        return hits;
    }

    public static void Run(string outp)
    {
        StringBuilder o = new StringBuilder();
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { o.AppendLine("no target"); System.IO.File.WriteAllText(outp, o.ToString()); return; }
        int pid = ps[0].Id;
        o.AppendLine("pid=" + pid);
        IntPtr h = OpenProcess(ALL, false, pid);
        if (h == IntPtr.Zero) { o.AppendLine("open err=" + Marshal.GetLastWin32Error()); System.IO.File.WriteAllText(outp, o.ToString()); return; }
        o.AppendLine("open ok");
        int before = NameHits(h);
        o.AppendLine("pre_hits=" + before);
        IntPtr mem = VirtualAllocEx(h, IntPtr.Zero, (IntPtr)0x200, 0x3000, 0x04);
        if (mem == IntPtr.Zero) { o.AppendLine("alloc err=" + Marshal.GetLastWin32Error()); System.IO.File.WriteAllText(outp, o.ToString()); return; }
        o.AppendLine("alloc ok @" + mem.ToString("x"));
        byte[] pb = Encoding.ASCII.GetBytes(DLL + "\0");
        IntPtr w;
        if (!WriteProcessMemory(h, mem, pb, (IntPtr)pb.Length, out w)) { o.AppendLine("wpm err=" + Marshal.GetLastWin32Error()); System.IO.File.WriteAllText(outp, o.ToString()); return; }
        o.AppendLine("wpm ok n=" + w.ToInt64());
        IntPtr ll = GetProcAddress(GetModuleHandle("kernel32"), "LoadLibraryA");
        o.AppendLine("loadlibrarya=0x" + ll.ToString("x"));
        IntPtr th = CreateRemoteThread(h, IntPtr.Zero, IntPtr.Zero, ll, mem, 0, IntPtr.Zero);
        if (th == IntPtr.Zero)
        {
            o.AppendLine("crt err=" + Marshal.GetLastWin32Error());
            int tried = 0;
            foreach (ProcessThread t in ps[0].Threads)
            {
                IntPtr oh = OpenThread(0x1F, false, (uint)t.Id);
                if (oh == IntPtr.Zero) { o.AppendLine("  ot err " + t.Id); continue; }
                if (QueueUserAPC(ll, oh, mem)) { tried++; o.Append(" apc:" + t.Id); }
                CloseHandle(oh);
                if (tried >= 24) break;
            }
            o.AppendLine();
            System.Threading.Thread.Sleep(2500);
            int ah = NameHits(h);
            o.AppendLine("apc_queued=" + tried + " post_hits=" + ah + " verdict=" + (ah > before ? "APC_OK" : "APC_FAIL"));
            System.IO.File.WriteAllText(outp, o.ToString());
            return;
        }
        o.AppendLine("crt ok handle=0x" + th.ToString("x"));
        uint w2 = WaitForSingleObject(th, 6000);
        IntPtr code;
        GetExitCodeThread(th, out code);
        o.AppendLine("wait=0x" + w2.ToString("x") + " exit=0x" + code.ToString("x") + " (0 = LoadLibrary failed)");
        CloseHandle(th);
        System.Threading.Thread.Sleep(700);
        int after = NameHits(h);
        o.AppendLine("post_hits=" + after + " verdict=" + (after > before ? "CRT_OK" : "CRT_FAIL"));
        System.IO.File.WriteAllText(outp, o.ToString());
        CloseHandle(h);
    }
}
'@ -Language CSharp -ErrorAction Stop
    [Inj]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}

