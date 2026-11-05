# p103_guest.ps1 -- is a 1450 PA durable or state-dependent? That decides hop vs retry.
#
# p100: only pa=0x200000 faults, neighbours fine. p99 + p101 already used three different landing
# buffers for that PA and all three got 1450, so the failure tracks the source address, not the
# destination. QueryWorkingSetEx is a dead end here (err=24 ERROR_BAD_LENGTH on all three call
# variants, skip it). What is left is the policy question:
#
#   durable  -> the PA is permanently unreadable (reserved / hypervisor-owned); a walk must HOP it
#   flaky    -> it was a transient (p96's BADEPICK 1450 would be the same thing); a walk RETRIES once
#
# Five reads of 0x200000, one second apart, fresh page each, then a control read of 0x300000 so a
# run of failures is proven to be the address and not a dead device.
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p103_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p103", $line) } catch { }
}
function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p103-v1'
$lock = Join-Path $dir '_p103.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 60) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p103 guest-entry version=$VER")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P103 {
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
}
'@ -ErrorAction SilentlyContinue

$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }

# one fresh landing page per attempt, kept alive until the end (via array) so no page is reused
$dsts = @()
function NewDst {
    $d = [P103]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
    [Runtime.InteropServices.Marshal]::Copy($canary, 0, $d, $PAGE)
    [P103]::VirtualLock($d, $PAGE) | Out-Null
    return $d
}

function DoRead([uint64]$pa, [IntPtr]$dst, [string]$tag) {
    $h = [P103]::CreateFileW('\\.\GIOV3', 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if (-not $h -or $h.ToInt64() -eq -1) { L ("  $tag open FAILED") ; return -1 }
    [Runtime.InteropServices.Marshal]::Copy($canary, 0, $dst, $PAGE)
    $ib = New-Object byte[] 24
    [Array]::Copy([BitConverter]::GetBytes($pa), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$dst.ToInt64()), 0, $ib, 16, 8)
    $ob = New-Object byte[] $PAGE
    $got = [uint32]0
    $ok = [P103]::DeviceIoControl($h, $IOCTL_READ, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [P103]::CloseHandle($h) | Out-Null
    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($dst, $back, 0, $PAGE)
    $d = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $d++ } }
    L ("  {0} pa=0x{1:x} ok={2} err={3} diff={4} head={5}" -f $tag, $pa, [int]$ok, [int]$err, $d, (Hex ($back[0..11])))
    if ($ok -and $d -gt 0) { return 1 }

$hits = 0
$fails = 0
for ($k = 1; $k -le 5; $k++) {
    $d = NewDst
    $dsts += $d
    $r = DoRead 0x200000 $d ("try" + $k)
    if ($r -eq -2) { $fails++ } elseif ($r -eq 1) { $hits++ }
    Start-Sleep -Milliseconds 800
}
$ctrlD = NewDst
$dsts += $ctrlD
$rc = DoRead 0x300000 $ctrlD 'ctrl'

L ("RESULT ok={0} err1450={1} ctrl={2}" -f $hits, $fails, $rc)
if ($rc -ne 1) { L 'VERDICT: CONTROL_FAILED' }
elseif ($fails -eq 5) { L 'VERDICT: PINNED_FAULT' }
elseif ($fails -gt 0) { L 'VERDICT: FLAKY_FAULT' }
else { L 'VERDICT: NOW_CLEAN' }
L ("VERDICT: P103_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
foreach ($d in $dsts) { [P103]::VirtualFree($d, 0, 0x8000) | Out-Null }

    if ($err -eq 1450) { return -2 }
    return 0
}
