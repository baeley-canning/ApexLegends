# h326 - if alloc is filtered, can we still (1) write into an EXISTING RW page and
#        (2) create a remote thread?  Those two are all a LoadLibraryW inject needs.
# Variable: the memory/thread op; target fixed = live EA-launched game.
param([int] $GamePid = 0, [switch] $Load, [string] $Dll = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll', [switch] $Elevate)
$outF = 'C:\h320x\h326.out'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    $extra = ' -Elevate'
    if ($GamePid -gt 0) { $extra += " -GamePid $GamePid" }
    if ($Load) { $extra += ' -Load' }
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra)
    exit 0
}
Remove-Item $outF -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class A26 {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [DllImport("kernel32", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr st, IntPtr start, IntPtr param, uint fl, out int tid);
    [DllImport("kernel32", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError=true)] public static extern bool GetExitCodeThread(IntPtr ht, out IntPtr code);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr GetModuleHandleW(string n);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr CreateToolhelp32Snapshot(uint f, int pid);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MODULEENTRY32W {
        public int dwSize, th32ModuleID, th32ProcessID, GlblcntUsage, ProccntUsage;
        public IntPtr modBaseAddr; public int modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExePath;
    }
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool Module32FirstW(IntPtr s, ref MODULEENTRY32W m);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool Module32NextW(IntPtr s, ref MODULEENTRY32W m);
    [StructLayout(LayoutKind.Sequential)] public struct MBI {
        public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect, a1;
        public IntPtr RegionSize; public uint State, Protect, Type, a2;
    }
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI m, IntPtr len);
    public static long ModuleBase(int pid, string name) {
        IntPtr s = CreateToolhelp32Snapshot(0x8, pid);
        if (s == (IntPtr)(-1)) return 0;
        MODULEENTRY32W m = new MODULEENTRY32W(); m.dwSize = Marshal.SizeOf(typeof(MODULEENTRY32W));
        bool ok = Module32FirstW(s, ref m); long f = 0;
        while (ok) { if (string.Equals(m.szModule, name, StringComparison.OrdinalIgnoreCase)) { f = m.modBaseAddr.ToInt64(); break; } ok = Module32NextW(s, ref m); }
        CloseHandle(s); return f;
    }
    // find a committed, writable, non-image, page-aligned region of >= need bytes
    public static long FindRw(IntPtr hp, int need, out string why) {
        why = "";
        MBI m; long a = 0x10000; int len = Marshal.SizeOf(typeof(MBI));
        int scanned = 0;
        while (a > 0 && a < 0x7FFFFFFF0000L && scanned < 400000) {
            scanned++;
            if (VirtualQueryEx(hp, (IntPtr)a, out m, (IntPtr)len) == IntPtr.Zero) { a += 0x10000; continue; }
            long rs = m.RegionSize.ToInt64(); if (rs <= 0) break;
            uint p = m.Protect & 0xFF;
            bool writable = (p == 0x04 || p == 0x08 || p == 0x40 || p == 0x80);
            if (m.State == 0x1000 && writable && m.Type != 0x1000000 && rs >= need)
                return m.BaseAddress.ToInt64() + 0x100;   // skip the region head
            a = m.BaseAddress.ToInt64() + rs;
        }
        why = "scanned " + scanned + " regions, none writable/non-image";
        return 0;
    }
}
'@
function W($m) { $m | Out-File -FilePath $outF -Append -Encoding utf8 }
W ("h326 - write + remote thread on the live game, elevated=$isAdmin - " + (Get-Date -Format 'HH:mm:ss'))
$g = if ($GamePid -gt 0) { Get-Process -Id $GamePid -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $g) { W 'NO live game'; W 'h326 DONE SKIP'; Get-Content $outF; return }
$pid0 = $g.Id
W "game     : pid=$pid0 threads=$($g.Threads.Count) ws=$([math]::Round($g.WorkingSet64/1MB,1))MB title='$($g.MainWindowTitle)'"
$h = [A26]::OpenProcess(0x1F0FFF, $false, $pid0)
W "handle   : 0x$($h.ToString('X'))"
if ($h -eq [IntPtr]::Zero) { W 'h326 DONE FAIL'; return }
W ("module   : kernel32 base=0x{0:X}" -f [A26]::ModuleBase($pid0, 'kernel32.dll'))


# (1) write into an existing RW page - same bytes first, then a real payload
$need = 1024
$why = ''
$rw = [A26]::FindRw($h, $need, [ref] $why)
if ($rw -eq 0) { W "find     : no usable RW page ($why)"; W 'h326 DONE FAIL'; [void][A26]::CloseHandle($h); Get-Content $outF; return }
W ("find     : RW page at 0x{0:X} (writable, non-image, >= {1} B)" -f $rw, $need)
$buf = New-Object byte[] 8
$got = [IntPtr]::Zero
$canRead = [A26]::ReadProcessMemory($h, [IntPtr] $rw, $buf, [IntPtr] 8, [ref] $got)
W ("read     : {0} err={1} ({2})" -f $canRead, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), (($buf | ForEach-Object { $_.ToString('X2') }) -join ' '))
$same = New-Object byte[] 8
if ($canRead) { [Array]::Copy($buf, $same, 8) } else { $same = [byte[]]@(0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41) }
$w1 = [A26]::WriteProcessMemory($h, [IntPtr] $rw, $same, [IntPtr] 8, [ref] $got)
W ("write    : same-bytes ok={0} err={1} done={2}" -f $w1, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), $got)

if ($Load) {
    $pathAddr = [IntPtr]($rw + 0x100)
    $bytes = [Text.Encoding]::Unicode.GetBytes($Dll + "`0")
    $wr = [A26]::WriteProcessMemory($h, $pathAddr, $bytes, [IntPtr] $bytes.Length, [ref] $got)
    $rb = New-Object byte[] $bytes.Length
    $null = [A26]::ReadProcessMemory($h, $pathAddr, $rb, [IntPtr] $rb.Length, [ref] $got)
    $match = (($rb -join ',') -eq ($bytes -join ','))
    W ("path     : write={0} err={1} readback={2} at 0x{3:X}" -f $wr, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), $match, $pathAddr.ToInt64())
    $k32 = [A26]::GetModuleHandleW('kernel32.dll')
    $ll = [A26]::GetProcAddress($k32, 'LoadLibraryW')
    $rk32 = [A26]::ModuleBase($pid0, 'kernel32.dll')
    $rll = [IntPtr]($rk32 + ($ll.ToInt64() - $k32.ToInt64()))
    W ("remote   : LoadLibraryW=0x{0:X}" -f $rll.ToInt64())
    $tid = 0
    $ht = [A26]::CreateRemoteThread($h, [IntPtr]::Zero, [IntPtr]::Zero, $rll, $pathAddr, 0, [ref] $tid)
    W ("thread   : CreateRemoteThread h={0} tid={1} err={2}" -f $ht, $tid, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    if ($ht -ne [IntPtr]::Zero) {
        [void][A26]::WaitForSingleObject($ht, 6000)
        $code = [IntPtr]::Zero
        [void][A26]::GetExitCodeThread($ht, [ref] $code)
        W ("thread   : exit=0x{0:X} (nonzero=module handle)" -f $code.ToInt64())
        [void][A26]::CloseHandle($ht)
    }
    Start-Sleep -Milliseconds 800
    W ("module   : apexcheat base=0x{0:X}" -f [A26]::ModuleBase($pid0, (Split-Path $Dll -Leaf)))
}

# (2) a remote thread that does nothing: Sleep(1500), so no module is touched
$k32b = [A26]::GetModuleHandleW('kernel32.dll')
$sl = [A26]::GetProcAddress($k32b, 'Sleep')
$rk32b = [A26]::ModuleBase($pid0, 'kernel32.dll')
$rsl = [IntPtr]($rk32b + ($sl.ToInt64() - $k32b.ToInt64()))
$tid2 = 0
$ht2 = [A26]::CreateRemoteThread($h, [IntPtr]::Zero, [IntPtr]::Zero, $rsl, [IntPtr] 200, 0, [ref] $tid2)
W ("thread2  : CreateRemoteThread(Sleep) h={0} tid={1} err={2}" -f $ht2, $tid2, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
if ($ht2 -ne [IntPtr]::Zero) { $w = [A26]::WaitForSingleObject($ht2, 4000); W ("thread2  : wait=0x{0:X} (0=ran and exited)" -f $w); [void][A26]::CloseHandle($ht2) }

$alive = [bool](Get-Process -Id $pid0 -ErrorAction SilentlyContinue)
W "after    : alive=$alive"
[void][A26]::CloseHandle($h)
if ($alive) { W 'RESULT: game survived the write/thread probes' } else { W 'RESULT: game DIED during the probes' }
W 'h326 DONE'
Get-Content $outF
