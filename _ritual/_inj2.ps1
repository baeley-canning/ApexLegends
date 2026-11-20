param([switch]$ElevatedChild)
$ErrorActionPreference = 'Stop'
if (-not $ElevatedChild)
{
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedChild'
    return
}
$d = Split-Path -Parent $PSCommandPath
$out = "$d\_inj2_out.txt"
'start' | Out-File -LiteralPath $out -Encoding ascii
try
{
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class VM
{
    static string OUT;
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr a, IntPtr s, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr s, out IntPtr w);
    [DllImport("kernel32", SetLastError=true)] static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr sa, IntPtr ss, IntPtr st, IntPtr par, uint fl, IntPtr tid);
    [DllImport("kernel32", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError=true)] static extern bool GetExitCodeThread(IntPtr h, out IntPtr code);
    [DllImport("kernel32")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("kernel32", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr hp, int cls, ref PBI pbi, int len, out int ret);
    [DllImport("ntdll")] static extern int NtOpenProcess(out IntPtr hp, uint acc, ref OA oa, ref CID cid);

    [StructLayout(LayoutKind.Sequential)] public struct OA { public uint Length; public IntPtr Root; public IntPtr Name; public uint Attr; public IntPtr Sec; public IntPtr Qos; }
    [StructLayout(LayoutKind.Sequential)] public struct CID { public IntPtr Handle; public IntPtr Pid; public IntPtr Tid; }
    [StructLayout(LayoutKind.Sequential)] public struct PBI
    {
        public IntPtr ExitStatus; public IntPtr PebBaseAddress; public IntPtr A0; public IntPtr A1;
        public IntPtr UniquePid; public IntPtr ParentPid; public IntPtr A2; public IntPtr A3;
        public IntPtr A4; public IntPtr A5; public IntPtr A6;
    }

    static void W(StringBuilder s, string x) { s.AppendLine(x); System.IO.File.AppendAllText(OUT, x + "\r\n"); }
    public static void Run(string outp)
    {
        StringBuilder o = new StringBuilder(); OUT = outp;
        
        Process[] ps = Process.GetProcessesByName("r5apex_dx12");
        if (ps.Length == 0) { W(o, "no target"); System.IO.File.WriteAllText(outp, o.ToString()); return; }
        int pid = ps[0].Id;
        W(o, "pid=" + pid);

        OA oa = new OA(); oa.Length = 48;
        CID cid = new CID(); cid.Pid = (IntPtr)pid;
        IntPtr h2;
        int ns = NtOpenProcess(out h2, 0x1F0FFF, ref oa, ref cid);
        W(o, "ntopenprocess st=0x" + ns.ToString("x8") + " h=0x" + h2.ToString("x"));
        h2 = OpenProcess(0x1F0FFF, false, pid);
        W(o, "openprocess => " + (h2 == IntPtr.Zero ? "err=" + Marshal.GetLastWin32Error() : "ok h=0x" + h2.ToString("x")));
        if (h2 == IntPtr.Zero) { System.IO.File.WriteAllText(outp, o.ToString()); return; }

        foreach (uint f in new uint[] { 0x3000u | 0x40u, 0x3000u | 0x04u, 0x2000u | 0x04u, 0x1000u | 0x04u })
        {
            IntPtr m = VirtualAllocEx(h2, IntPtr.Zero, (IntPtr)0x100, f & 0x7000, f & 0xFF);
            W(o, "alloc flags=0x" + f.ToString("x") + " => " + (m == IntPtr.Zero ? "err=" + Marshal.GetLastWin32Error() : "ok @" + m.ToString("x")));
        }

        PBI pbi = new PBI(); int rr;
        int qs = NtQueryInformationProcess(h2, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out rr);
        W(o, "pebquery st=0x" + qs.ToString("x8") + " peb=0x" + pbi.PebBaseAddress.ToString("x"));
        if (qs != 0 || pbi.PebBaseAddress == IntPtr.Zero) return;

        IntPtr scratch = (IntPtr)(pbi.PebBaseAddress.ToInt64() + 0xF00);
        byte[] probe = new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 };
        IntPtr w;
        bool wp = WriteProcessMemory(h2, scratch, probe, (IntPtr)8, out w);
        W(o, "wpm selfbuf st=" + (wp ? "ok n=" + w.ToInt64() : "err=" + Marshal.GetLastWin32Error()));

        byte[] path = Encoding.ASCII.GetBytes("C:\\Windows\\System32\\avifil32.dll\0");
        bool wp2 = WriteProcessMemory(h2, (IntPtr)(scratch.ToInt64() + 0x80), path, (IntPtr)path.Length, out w);
        W(o, "wpm path st=" + (wp2 ? "ok n=" + w.ToInt64() : "err=" + Marshal.GetLastWin32Error()));

        IntPtr ll = GetProcAddress(GetModuleHandle("kernel32"), "LoadLibraryA");
        IntPtr th = CreateRemoteThread(h2, IntPtr.Zero, IntPtr.Zero, ll, (IntPtr)(scratch.ToInt64() + 0x80), 0, IntPtr.Zero);
        W(o, "crt " + (th == IntPtr.Zero ? "err=" + Marshal.GetLastWin32Error() : "ok h=0x" + th.ToString("x")));
        if (th != IntPtr.Zero)
        {
            WaitForSingleObject(th, 5000);
            IntPtr code; GetExitCodeThread(th, out code);
            W(o, "exit=0x" + code.ToString("x"));
            CloseHandle(th);
        }
        System.IO.File.WriteAllText(outp, o.ToString());
    }
}
'@ -Language CSharp -ErrorAction Stop
    [VM]::Run($out)
}
catch
{
    ('EX ' + $_.Exception.Message) | Out-File -LiteralPath $out -Encoding ascii -Append
}
