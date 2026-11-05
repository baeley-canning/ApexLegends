$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p102_guest.txt'
$base = 'http://10.0.2.2:8080'

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p102", $line) } catch { }
}

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
L ("=== p102 guest-entry version=p102-v1")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P102 {
    [StructLayout(LayoutKind.Sequential)]
    public struct WSE { public IntPtr VA; public UInt64 Attr; }
    [DllImport("kernel32", SetLastError=true)]
    public static extern bool VirtualLock(IntPtr p, uint n);
    [DllImport("kernel32", SetLastError=true)]
    public static extern IntPtr VirtualAlloc(IntPtr a, uint n, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)]
    public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
    [DllImport("kernel32", SetLastError=true, EntryPoint="K32QueryWorkingSetEx")]
    public static extern bool KWSE(IntPtr proc, [In, Out] WSE[] info, uint n);
    [DllImport("psapi", SetLastError=true)]
    public static extern bool QueryWorkingSetEx(IntPtr proc, [In, Out] WSE[] info, uint n);
}
'@ -ErrorAction SilentlyContinue

$p = [P102]::VirtualAlloc([IntPtr]::Zero, 0x1000, 0x3000, 0x04)
if (-not $p -or $p.ToInt64() -eq 0) { L 'VERDICT: NO_ALLOC'; L ("VERDICT: P102_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss')) ; exit 0 }
[Runtime.InteropServices.Marshal]::WriteByte($p, 0, 0x41)
$lk = [P102]::VirtualLock($p, 0x1000)
$lerr = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
L ("alloc=0x{0:x} lock={1} lock_err={2}" -f $p.ToInt64(), [int]$lk, $lerr)
L ("sizeof(WSE)=" + [Runtime.InteropServices.Marshal]::SizeOf([type]'P102+WSE'))

function TryWSE([IntPtr]$h, [string]$tag) {
    $q = New-Object 'P102+WSE[]' 1
    $q[0].VA = $p
    $q[0].Attr = 0
    $r = [P102]::KWSE($h, $q, 1)
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $a = $q[0].Attr
    L ("{0} h=0x{1:x} r={2} err={3} attr=0x{4:x} pfn=0x{5:x}" -f $tag, $h.ToInt64(), [int]$r, $e, $a, (($a -shr 32) -band 0xFFFFFFF))
    return $r
}

$okA = TryWSE ([P102]::GetCurrentProcess()) 'A_pseudo'
$self = [P102]::OpenProcess(0x410, $false, [uint32]$PID)
$okB = $false
if ($self -and $self.ToInt64() -ne 0) { $okB = TryWSE $self 'B_openproc' } else { L ('B_openproc FAILED err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }

$q2 = New-Object 'P102+WSE[]' 1
$q2[0].VA = $p
$q2[0].Attr = 0
$r3 = [P102]::QueryWorkingSetEx([P102]::GetCurrentProcess(), $q2, 1)
L ("C_psapi r={0} err={1} attr=0x{2:x}" -f [int]$r3, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), $q2[0].Attr)

if ($okA -or $okB -or $r3) { L 'VERDICT: PFN_OK' } else { L 'VERDICT: PFN_UNAVAILABLE' }
L ("VERDICT: P102_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
