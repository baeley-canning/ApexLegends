# ============================================================================
# _ritual\ov71_handle.ps1 - WHICH rights survive the EAAC access jail.
#
# ov70 proved the handle from OpenProcess(ALL) is granted but then refuses every
# VM operation: VirtualAllocEx(RW)=5, ReadProcessMemory=fail on all committed RW
# regions.  That is the signature of an Ob callback that masks VM rights at
# handle creation.  Before spending a kernel driver (BYOVD + DSE off) on this,
# measure whether a *narrow* request is granted where ALL is masked.
# ============================================================================
param([int] $Pid0 = 0, [switch] $Elevate)

$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'ov71_handle.out'
$utf8 = [Text.UTF8Encoding]::new($false)
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n", $utf8); Write-Host $s }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
    $a = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevate -Pid0 {1}' -f $PSCommandPath, $Pid0)
    Start-Process powershell -Verb RunAs -ArgumentList $a
    Write-Host 'ov71: relaunched elevated'
    exit 0
}
[IO.File]::WriteAllText($out, ("ov71 - rights probe - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $utf8)

$p = if ($Pid0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $p) { W 'FAIL no game'; exit 1 }
$procId = [int] $p.Id

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp71 {
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, IntPtr size, out IntPtr done);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr CreateRemoteThread(IntPtr hp, IntPtr sa, IntPtr stack, IntPtr start, IntPtr param, uint flags, out int tid);
    [DllImport("kernel32", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr GetModuleHandleW(string n);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("kernel32", SetLastError = true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI mbi, IntPtr len);
    [StructLayout(LayoutKind.Sequential, Size = 48)]
    public struct MBI { public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect; public ushort PartitionId; public ushort pad0; public ulong RegionSize; public uint State; public uint Protect; public uint Type; public uint pad1; }
    public static ulong FindRw(IntPtr hp) {
        byte[] probe = new byte[16];
        for (ulong a = 0x10000; a < 0x7FFE0000UL; ) {
            MBI m;
            IntPtr q = VirtualQueryEx(hp, new IntPtr((long) a), out m, new IntPtr(Marshal.SizeOf(typeof(MBI))));
            if (q == IntPtr.Zero) { a += 0x1000; continue; }
            ulong rb = (ulong) m.BaseAddress.ToInt64(); ulong rs = m.RegionSize; uint pr = m.Protect;
            if (m.State == 0x1000 && (pr & 0x04) != 0 && (pr & 0x40) == 0 && rs > 0x4000) {
                IntPtr got;
                if (ReadProcessMemory(hp, new IntPtr((long) rb), probe, new IntPtr(probe.Length), out got)) return rb;
            }
            a = rb + (rs > 0 ? rs : 0x1000);
        }
        return 0;
    }
}
'@

$localK32 = [Sp71]::GetModuleHandleW('kernel32.dll')
$tick     = [Sp71]::GetProcAddress($localK32, 'GetTickCount')
$sets = @(
    @{ n = 'ALL 0x1F0FFF';                  v = 0x1F0FFF },
    @{ n = 'VM_OPER|VM_READ|VM_WRITE 0x38'; v = 0x38 },
    @{ n = 'VM_READ|VM_WRITE 0x30';         v = 0x30 },
    @{ n = 'VM_OPER|VM_WRITE 0x28';         v = 0x28 },
    @{ n = 'CREATE_THREAD|VM_OPER 0x0A';    v = 0x0A }
)
foreach ($s in $sets) {
    W ('---- ' + $s.n)
    $hp = [Sp71]::OpenProcess([uint32] $s.v, $false, $procId)
    if ($hp -eq [IntPtr]::Zero) { W ("  open : FAIL err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); continue }
    W "  open : ok h=$hp"
    $buf = New-Object byte[] 16; $done = [IntPtr]::Zero
    $r = [Sp71]::ReadProcessMemory($hp, [IntPtr][int64]0x7FFE0000, $buf, [IntPtr]16, [ref] $done)
    W ("  rpm  : ok={0} err={1}" -f $r, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    $rw = [Sp71]::FindRw($hp)
    if ($rw -ne 0) {
        $orig = New-Object byte[] 16; $d2 = [IntPtr]::Zero
        $null = [Sp71]::ReadProcessMemory($hp, [IntPtr][int64]$rw, $orig, [IntPtr]16, [ref] $d2)
        $w = [Sp71]::WriteProcessMemory($hp, [IntPtr][int64]$rw, $orig, [IntPtr]16, [ref] $d2)
        W ("  wpm  : at 0x{0:X} ok={1} err={2}" -f $rw, $w, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    } else { W '  wpm  : no readable RW region -> not tested' }
    $m = [Sp71]::VirtualAllocEx($hp, [IntPtr]::Zero, [IntPtr]0x1000, 0x3000, 0x04)
    W ("  vaex : ok={0} err={1}" -f ($m -ne [IntPtr]::Zero), [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    $tid = 0
    $ht = [Sp71]::CreateRemoteThread($hp, [IntPtr]::Zero, [IntPtr]::Zero, $tick, [IntPtr]::Zero, 0, [ref] $tid)
    if ($ht -eq [IntPtr]::Zero) { W ("  crt  : FAIL err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
    else { $w2 = [Sp71]::WaitForSingleObject($ht, 3000); W ("  crt  : ok tid={0} wait=0x{1:X}" -f $tid, $w2) }
    [void][Sp71]::CloseHandle($hp)
}
W ''
W "RESULT: rights probe done"

W "target   : pid=$procId title='$($p.MainWindowTitle)'  elevated=$isAdmin"
