# h325 - which remote-memory ops does the protected live game accept?
# Control: MsMpEng (a real PPL) so "generic protected process" is separated from
# "EAAC filter".  One variable: the operation, against one fixed target each.
param([int] $GamePid = 0, [switch] $Elevate)
$outF = 'C:\h320x\h325.out'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    $extra = ' -Elevate'
    if ($GamePid -gt 0) { $extra += " -GamePid $GamePid" }
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra)
    exit 0
}
Remove-Item $outF -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class A25 {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, IntPtr size, uint type);
    [DllImport("kernel32", SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [DllImport("kernel32", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll")] public static extern int NtAllocateVirtualMemory(IntPtr hp, ref IntPtr addr, IntPtr zeroBits, ref IntPtr size, uint type, uint prot);
    [StructLayout(LayoutKind.Sequential)] public struct MBI {
        public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect, a1;
        public IntPtr RegionSize; public uint State, Protect, Type, a2;
    }
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI mbi, IntPtr len);

    public static string Alloc(IntPtr h, uint type, uint prot) {
        IntPtr m = VirtualAllocEx(h, IntPtr.Zero, (IntPtr)120, type, prot);
        int e = Marshal.GetLastWin32Error();
        if (m == IntPtr.Zero) return "FAILED err=" + e;
        string r = "OK at 0x" + m.ToString("X");
        VirtualFreeEx(h, m, IntPtr.Zero, 0x8000);
        return r;
    }
    public static string NtAlloc(IntPtr h, uint prot) {
        IntPtr addr = IntPtr.Zero, size = (IntPtr)120;
        int st = NtAllocateVirtualMemory(h, ref addr, IntPtr.Zero, ref size, 0x3000, prot);
        if (st < 0) return string.Format("FAILED status=0x{0:X8}", st);
        string r = string.Format("OK at 0x{0:X} (status 0x{1:X8})", addr.ToInt64(), st);
        VirtualFreeEx(h, addr, IntPtr.Zero, 0x8000);
        return r;
    }
    public static string NoopWrite(IntPtr h) {
        MBI m; IntPtr any = IntPtr.Zero;
        long a = 0x10000;
        while (a < 0x7FFFFFFF0000L) {
            if (VirtualQueryEx(h, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) { a += 0x10000; continue; }
            long rs = m.RegionSize.ToInt64(); if (rs <= 0) break;
            if (m.State == 0x1000) { any = m.BaseAddress; break; }
            a = m.BaseAddress.ToInt64() + rs;
        }
        if (any == IntPtr.Zero) return "no committed region found (VirtualQueryEx filtered?)";
        byte[] buf = new byte[8]; IntPtr got;
        if (!ReadProcessMemory(h, any, buf, (IntPtr)8, out got)) return "read failed err=" + Marshal.GetLastWin32Error();
        if (!WriteProcessMemory(h, any, buf, (IntPtr)8, out got)) return "same-bytes write FAILED err=" + Marshal.GetLastWin32Error();
        return "same-bytes write OK at 0x" + any.ToString("X");
    }
    public static string Q(IntPtr h) {
        MBI m;
        IntPtr r = VirtualQueryEx(h, (IntPtr)0x140000000L, out m, (IntPtr)Marshal.SizeOf(typeof(MBI)));
        if (r == IntPtr.Zero) return "VirtualQueryEx failed err=" + Marshal.GetLastWin32Error();
        return string.Format("VirtualQueryEx OK: base=0x{0:X} size=0x{1:X} state=0x{2:X} prot=0x{3:X} type=0x{4:X}",
            m.BaseAddress.ToInt64(), m.RegionSize.ToInt64(), m.State, m.Protect, m.Type);
    }
}
'@
function W($m) { $m | Out-File -FilePath $outF -Append -Encoding utf8 }
W ("h325 - remote memory ops, elevated=$isAdmin - " + (Get-Date -Format 'HH:mm:ss'))

$g = if ($GamePid -gt 0) { Get-Process -Id $GamePid -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $g) { W 'NO live game'; W 'h325 DONE SKIP'; Get-Content $outF; return }
W "game     : pid=$($g.Id)"
$h = [A25]::OpenProcess(0x1F0FFF, $false, $g.Id)
W "handle   : 0x$($h.ToString('X'))"
if ($h -ne [IntPtr]::Zero) {
    W ('  trimd) OpenProcess(VM_W|OP only) : ' + $(if ([A25]::OpenProcess(0x28, $false, $g.Id) -ne [IntPtr]::Zero) { 'GRANTED' } else { 'denied' }))
    W ('  a) alloc RWX  commit|reserve     : ' + [A25]::Alloc($h, 0x3000, 0x40))
    W ('  b) alloc RW   commit|reserve     : ' + [A25]::Alloc($h, 0x3000, 0x04))
    W ('  c) alloc R    commit|reserve     : ' + [A25]::Alloc($h, 0x3000, 0x02))
    W ('  d) alloc EXEC commit|reserve     : ' + [A25]::Alloc($h, 0x3000, 0x20))
    W ('  e) NtAllocateVirtualMemory RWX  : ' + [A25]::NtAlloc($h, 0x40))
    W ('  f) NtAllocateVirtualMemory RW   : ' + [A25]::NtAlloc($h, 0x04))
    W ('  g) ' + [A25]::Q($h))
    W ('  h) ' + [A25]::NoopWrite($h))
    [void][A25]::CloseHandle($h)
}
# control: a real PPL process, so "protected" alone is not the explanation
$ppm = @(Get-Process MsMpEng -ErrorAction SilentlyContinue) | Select-Object -First 1
if ($ppm) {
    $h2 = [A25]::OpenProcess(0x1F0FFF, $false, $ppm.Id)
    if ($h2 -eq [IntPtr]::Zero) { W "ppl      : MsMpEng pid=$($ppm.Id) OpenProcess denied err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    else {
        W "ppl      : MsMpEng pid=$($ppm.Id) handle ok"
        W ('  i) alloc RWX (PPL control)      : ' + [A25]::Alloc($h2, 0x3000, 0x40))
        [void][A25]::CloseHandle($h2)
    }
} else { W 'ppl      : MsMpEng not running - control skipped' }
W 'RESULT: rows above name the op; the game column is the EAAC filter map'
W 'h325 DONE'
Get-Content $outF

