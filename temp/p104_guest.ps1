# p104_guest.ps1 -- rerun of the durability question with step markers, control read first.
#
# p103 logged its entry line at 12:21:05 and then nothing for 90 s: it hung somewhere between
# Add-Type and the first DoRead, and DoRead only logs *after* the IOCTL returns, so a hang inside
# the first DeviceIoControl looks identical to a hang in setup. p104 fixes the attribution:
#   - a marker before/after Add-Type and after each allocation, so setup hangs are visible
#   - a control read of the known-good 0x100000 FIRST, so "hung on the bad PA" vs "hung on startup"
#     are distinguishable by which marker is last
#   - a shorter tail (3 attempts), 800 ms apart, still enough to separate pinned from flaky.
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p104_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Host $line
    try { $null = (New-Object Net.WebClient).UploadString("$base/log?vm=p104", $line) } catch { }
}
function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p104-v4'
$lock = Join-Path $dir '_p104.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 45) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p104 guest-entry version=$VER marker=start")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P104 {
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
L ("marker=typed class=" + ("P104" -as [type]).FullName)

$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }
L ("marker=canary n=" + $canary.Length)


$dsts = @()
function NewDst([string]$tag) {
    $d = [P104]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
    L ("marker=alloc_{0} at=0x{1:x}" -f $tag, $d.ToInt64())
    [Runtime.InteropServices.Marshal]::Copy([byte[]]$canary, [int]0, [IntPtr]$d, [int]$PAGE)
    [P104]::VirtualLock($d, $PAGE) | Out-Null
    return $d
}

function DoRead([uint64]$pa, [IntPtr]$dst, [string]$tag) {
    $h = [P104]::CreateFileW('\\.\GIOV3', 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if (-not $h -or $h.ToInt64() -eq -1) { L ("  $tag open FAILED") ; return -1 }
    L ("  $tag opened -> ioctl")
    [Runtime.InteropServices.Marshal]::Copy([byte[]]$canary, [int]0, [IntPtr]$dst, [int]$PAGE)
    $ib = New-Object byte[] 24
    [Array]::Copy([BitConverter]::GetBytes($pa), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$dst.ToInt64()), 0, $ib, 16, 8)
    $ob = New-Object byte[] $PAGE
    $got = [uint32]0
    $ok = [P104]::DeviceIoControl($h, $IOCTL_READ, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    L ("  $tag ioctl returned -> closing")
    [P104]::CloseHandle($h) | Out-Null
    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy([IntPtr]$dst, [byte[]]$back, [int]0, [int]$PAGE)
    $d = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $d++ } }
    L ("  {0} pa=0x{1:x} ok={2} err={3} diff={4} head={5}" -f $tag, $pa, [int]$ok, [int]$err, $d, (Hex ($back[0..11])))
    if ($ok -and $d -gt 0) { return 1 }
    if ($err -eq 1450) { return -2 }
    return 0
}

$c = NewDst 'ctrl'
$dsts += $c
$rc = DoRead 0x100000 $c 'ctrl'
L ("marker=control_done rc=" + $rc)

$hits = 0
$fails = 0
for ($k = 1; $k -le 3; $k++) {
    $d = NewDst ("t" + $k)
    $dsts += $d
    $r = DoRead 0x200000 $d ("try" + $k)
    if ($r -eq -2) { $fails++ } elseif ($r -eq 1) { $hits++ }
    Start-Sleep -Milliseconds 800
}

L ("RESULT bad_ok={0} bad_1450={1} ctrl={2}" -f $hits, $fails, $rc)
if ($rc -ne 1) { L 'VERDICT: CONTROL_FAILED' }
elseif ($fails -eq 3) { L 'VERDICT: PINNED_FAULT' }
elseif ($fails -gt 0) { L 'VERDICT: FLAKY_FAULT' }
else { L 'VERDICT: NOW_CLEAN' }
L ("VERDICT: P104_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
foreach ($d in $dsts) { [P104]::VirtualFree($d, 0, 0x8000) | Out-Null }



