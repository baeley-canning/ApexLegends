# p97_guest.ps1 -- VM bench twin of temp\p97_shapes.py.
#
# Why it exists: p84/p90/p84b kill the HOST at gdrv3+0x2e81 with 0x3B/0xC0000005 on the
# ioctl that follows a successful MAP_K, so the sweep belongs in the snapshotted guest
# (AGENTS.md R1), where a bugcheck recycles a VM instead of the daily driver.
#
# Difference from the host script, and the only reason this is a new probe (R5): the
# progress line is posted BEFORE each DeviceIoControl, not after. A guest bugcheck then
# leaves the exact failing argument tuple on disk and on the host log.
#
# Delivered by the p37 harness: payload\cur.ps1 is fetched and run as SYSTEM every tick
# (run.cmd -> once.cmd -> powershell -File cur.ps1). Output goes to
# http://10.0.2.2:8080/log?vm=p97 (-> C:\p37vm\guest-p97.log) and C:\Users\Public\p37\_p97_guest.txt.
# Read-only against the driver: no unmap of anything we did not map, no device writes.
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p97_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$IOCTL_MAPK = 0xC3502019L
$IOCTL_ALLOC = 0xC3502800L
$IOCTL_TRANS = 0xC350280CL
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p97", $line) } catch { }
}

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p97b-v8'
$SKIP_DST0 = $true   # dst=0 wedges the guest before the close path; off until the close fix is proven
$lock = Join-Path $dir '_p97.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 45) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p97b host-entry version=$VER")
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P97 {
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
    [DllImport("kernel32", SetLastError=true)]
    public static extern uint GetFileType(IntPtr h);
}
'@ -ErrorAction SilentlyContinue

function Call([uint32]$code, [byte[]]$ib, [int]$outlen) {
    $ob = New-Object byte[] ([Math]::Max($outlen, 16))
    $got = [uint32]0
    $ok = [P97]::DeviceIoControl($h, $code, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $desc = 'ok=' + [int]$ok + ' err=' + [int]$err + ' got=' + [int]$got
    return @{ ok = $ok; err = $err; out = $ob; got = [int]$got; desc = $desc }
}
function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

$stamp = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$up = 0
if ($os) { $up = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds }
$svc = (sc.exe query gdrv3 2>&1 | Select-String 'STATE') -join ';'
$qc = (sc.exe qc gdrv3 2>&1 | Select-String 'BINARY_PATH_NAME') -join ';'
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$rammb = 0
if ($cs) { $rammb = [int]($cs.TotalPhysicalMemory / 1MB) }
L "=== p97-guest start $stamp up=${up}s ram=${rammb}MB"
L "pre svc: $($svc.Trim())"
L "qc: $($qc.Trim())"

$h = [IntPtr]::Zero
foreach ($dev in '\\.\GIOV3', '\\.\gdrv3', '\\.\GIO', '\\.\gio') {
    $try = [P97]::CreateFileW($dev, 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    $tv = 0
    if ($try) { $tv = $try.ToInt64() }
    $oe = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($tv -ne 0 -and $tv -ne -1) { $h = $try ; L ("open ok $dev handle=$tv filetype=" + [P97]::GetFileType($h)) ; break }
    L ("open FAILED $dev h=$tv err=$oe")
}
if (-not $h -or $h.ToInt64() -eq 0) { L 'no device -> abort' ; L 'VERDICT: NO_DEVICE' ; exit 1 }

$dstp = [P97]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
if (-not $dstp -or $dstp -eq [IntPtr]::Zero) { L 'VirtualAlloc FAILED'; exit 1 }
$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }
[Runtime.InteropServices.Marshal]::Copy($canary, 0, $dstp, $PAGE)
$locked = [P97]::VirtualLock($dstp, $PAGE)
L ("dst user va 0x{0:x} locked={1}" -f $dstp.ToInt64(), [int]$locked)

# --- positive control: translate our own buffer, read that PA back, compare ---
# Guest history (STATE 11-02, probeE/F): 0x280C and 0x2019 both returned 1450 here, so a
# translate failure is expected in the VM and must not end the probe - the shape sweep only
# needs *a* PA, and a read failure is cheap inside a snapshot.
$pa = 0
L ("BEFORE trans va=0x{0:x} len=8" -f $dstp.ToInt64())
$r = Call $IOCTL_TRANS ([BitConverter]::GetBytes([uint64]$dstp.ToInt64())) 0x10
if ($r.ok) {
    $pa = [BitConverter]::ToUInt64($r.out, 0)
    L ("trans ok got={0} pa=0x{1:x}" -f $r.got, $pa)
} else { L ("trans FAILED " + $r.desc) }

$ib = New-Object byte[] 24
foreach ($cand in 0x100000, 0x200000, 0x10000000, 0x40000000) {
    if ($pa) { break }
    [Array]::Copy([BitConverter]::GetBytes([uint64]$cand), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$dstp.ToInt64()), 0, $ib, 16, 8)
    L ("BEFORE read-fallback pa=0x{0:x} size=0x{1:x} dst=0x{2:x}" -f $cand, $PAGE, $dstp.ToInt64())
    $r = Call $IOCTL_READ $ib $PAGE
    if ($r.ok) { $pa = $cand ; L ("  fallback read accepted pa=0x{0:x} got={1}" -f $cand, $r.got) }
    else { L ("  fallback read rejected pa=0x{0:x} {1}" -f $cand, $r.desc) }
}
if (-not $pa) { L 'no usable PA -> shape sweep skipped'; [P97]::CloseHandle($h) | Out-Null ; L 'VERDICT: NO_PA'; exit 2 }

$diff = -1
[Array]::Copy([BitConverter]::GetBytes([uint64]$pa), 0, $ib, 0, 8)
[Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
[Array]::Copy([BitConverter]::GetBytes([uint64]$dstp.ToInt64()), 0, $ib, 16, 8)
L ("BEFORE read pa=0x{0:x} size=0x{1:x} dst=0x{2:x}" -f $pa, $PAGE, $dstp.ToInt64())
$r = Call $IOCTL_READ $ib $PAGE
if (-not $r.ok) {
    L ("read FAILED err={0}" -f [int]$r.err)
} else {
    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($dstp, $back, 0, $PAGE)
    $diff = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $diff++ } }
    $head = Hex ($back[0..15])
    L ("read ok got={0} head={1} diff={2}" -f $r.got, $head, $diff)
}

function Pack([uint64]$a, [uint32]$b, [uint32]$c, [uint64]$dd) {
    $b24 = New-Object byte[] 24
    [Array]::Copy([BitConverter]::GetBytes($a), 0, $b24, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes($b), 0, $b24, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes($c), 0, $b24, 12, 4)
    [Array]::Copy([BitConverter]::GetBytes($dd), 0, $b24, 16, 8)
    return $b24
}
function CanaryHead { return (Hex ($canary[0..7])) }
function Kva([uint64]$kva) {
    if ($kva -eq 0) { return 'kva=0' }
    try {
        $k8 = New-Object byte[] 8
        [Runtime.InteropServices.Marshal]::Copy([IntPtr][int64]$kva, $k8, 0, 8)
        return ("kva=0x{0:x} head={1}" -f $kva, (Hex $k8))
    } catch { return ("kva=0x{0:x} unreadable" -f $kva) }
}

# Second translated page: the host dies on the SECOND map call, not the first.
$dstp2 = [P97]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
[Runtime.InteropServices.Marshal]::Copy($canary, 0, $dstp2, $PAGE)
[P97]::VirtualLock($dstp2, $PAGE) | Out-Null
L ("BEFORE trans2 va=0x{0:x} len=8" -f $dstp2.ToInt64())
$r = Call $IOCTL_TRANS ([BitConverter]::GetBytes([uint64]$dstp2.ToInt64())) 0x10
$pa2 = 0
if ($r.ok) { $pa2 = [BitConverter]::ToUInt64($r.out, 0) ; L ("trans2 ok pa2=0x{0:x}" -f $pa2) }
else { L ("trans2 FAILED err={0}" -f $r.err) }

$want = CanaryHead

# The actual host killer: a second map immediately after a successful one, NULL dst.
if ($pa2) {
    $ib2 = Pack $pa2 $PAGE 0 0
    L ("BEFORE mapK SECOND-TARGET dst=0 pa2=0x{0:x} in={1}" -f $pa2, (Hex $ib2))
    $r = Call $IOCTL_MAPK $ib2 0x10
    if ($r.ok) {
        $kva = [BitConverter]::ToUInt64($r.out, 0)
        L ("  second ok=1 got={0} {1}" -f $r.got, (Kva $kva))
    } else { L ("  second " + $r.desc) }
}

L '--- TRANSLATE length sweep on dst ---'
foreach ($n in 8, 12, 16, 4) {
    $ibb = New-Object byte[] $n
    $full = [BitConverter]::GetBytes([uint64]$dstp.ToInt64())
    [Array]::Copy($full, 0, $ibb, 0, [Math]::Min($n, 8))
    L ("BEFORE trans len={0} in={1}" -f $n, (Hex $ibb))
    $r = Call $IOCTL_TRANS $ibb 0x10
    L ("  len={0} {1} out={2}" -f $n, $r.desc, (Hex ($r.out[0..7])))
}

L '--- ALLOC length sweep ---'
$allocs = @(
    @{ n = 'u32'; l = 4 }, @{ n = 'u64'; l = 8 }, @{ n = 'u32,u32'; l = 8 },
    @{ n = 'u32x3'; l = 12 }, @{ n = 'QIIQ'; l = 24 }
)
foreach ($a in $allocs) {
    $ibb = New-Object byte[] $a.l
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ibb, 0, 4)
    L ("BEFORE alloc {0} in={1}" -f $a.n, (Hex $ibb))
    $r = Call $IOCTL_ALLOC $ibb 0x10
    L ("  {0} {1} out={2}" -f $a.n, $r.desc, (Hex ($r.out[0..15])))
}

L ("want head={0}" -f $want)
L ("RESULT read_selfdiff={0} second_target_pa=0x{1:x}" -f $diff, $pa2)

# === MAP_K shape sweep goes LAST: the dst=0 variant can bugcheck the guest and
# would otherwise hide the trans/alloc sweeps behind a reboot. ===
L '--- mapK in-struct variants, control page, len=24 ---'
$scr = 0
if ($dstp2) { $scr = $dstp2.ToInt64() }
$qqq = New-Object byte[] 24
[Array]::Copy([BitConverter]::GetBytes([uint64]$pa), 0, $qqq, 0, 8)
[Array]::Copy([BitConverter]::GetBytes([uint64]$PAGE), 0, $qqq, 8, 8)
[Array]::Copy([BitConverter]::GetBytes([uint64]$dstp.ToInt64()), 0, $qqq, 16, 8)
$variants = @( @{ n = 'QIIQ dst'; ib = (Pack $pa $PAGE 0 $dstp.ToInt64()) } )
if ($scr) { $variants += @{ n = 'QIIQ scratch'; ib = (Pack $pa $PAGE 0 $scr) } }
$variants += @{ n = 'QQQ'; ib = $qqq }
$variants += @{ n = 'QIIQ sz=0'; ib = (Pack $pa 0 0 $dstp.ToInt64()) }
if (-not $SKIP_DST0) { $variants += @{ n = 'QIIQ dst=0'; ib = (Pack $pa $PAGE 0 0) } }

foreach ($x in $variants) {
    L ("BEFORE mapK {0} in={1}" -f $x.n, (Hex $x.ib))
    $r = Call $IOCTL_MAPK $x.ib 0x20
    if (-not $r.ok) { L ("  {0} {1}" -f $x.n, $r.desc) ; continue }
    $kva = [BitConverter]::ToUInt64($r.out, 0)
    L ("  {0} ok=1 got={1} out={2} {3}" -f $x.n, $r.got, (Hex ($r.out[0..15])), (Kva $kva))
}
L '--- mapK sweep end ---'

# --- close FIRST, free AFTER (p91 fix, PS edition) ---------------------------------
# STATE 11-05: the driver's write is a deferred dword memcpy that runs at IRP_MJ_CLOSE,
# dest = the request's dst field. Freeing dst before CloseHandle decommits the landing
# page and the copy faults at gdrv3+0x2e81. Keep both pages committed across the close,
# read the landing page back *after* the close returns, and only then release.
if ($h) { [P97]::CloseHandle($h) | Out-Null }
L ("closed $(Get-Date -f 'HH:mm:ss')")

$diff2 = -1
if ($dstp) {
    $back2 = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($dstp, $back2, 0, $PAGE)
    $diff2 = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back2[$i] -ne $canary[$i]) { $diff2++ } }
    L ("post-close dst head={0} diff={1}" -f (Hex ($back2[0..15])), $diff2)
}
L ("RESULT2 postclose_selfdiff={0} preclose_selfdiff={1}" -f $diff2, $diff)
if ($dstp) { [P97]::VirtualFree($dstp, 0, 0x8000) | Out-Null }
if ($dstp2) { [P97]::VirtualFree($dstp2, 0, 0x8000) | Out-Null }
L "freed"
L "VERDICT: P97VM_DONE $stamp"
