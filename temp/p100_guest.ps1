# p100_guest.ps1 -- why does READ return 1450 for some PAs? (VM bench)
#
# p99 (READ_FAITHFUL) showed the read is address-faithful, repeatable and clean on failure:
# pa=0x200000 returned err=1450 and left the destination page untouched (diff=0). That 1450 is
# the same code p96 got on a genuine EPROCESS page (BADEPICK), so it — not the read itself — is
# what stands between us and player data.
#
# This probe measures where the working window ends. One PA per open/close cycle with its own
# landing page, so every verdict is unambiguous and each cycle also re-tests open/close stability.
# Boundary shapes:
#   all ok up to N, then all 1450   -> fixed window (driver maps a bounded aperture)
#   scattered 1450                  -> per-range collision (e.g. the driver's own image / our buffers)
#   all ok                          -> p96's 1450 was transient, retry with fresh state
$ErrorActionPreference = 'Continue'
trap { L ('EXC ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message + ' @L' + $_.InvocationInfo.ScriptLineNumber) ; continue }
$dir = 'C:\Users\Public\p37'
$out = Join-Path $dir '_p100_guest.txt'
$base = 'http://10.0.2.2:8080'
$IOCTL_READ = 0xC3502014L
$PAGE = 0x1000

function L([string]$m) {
    $line = (Get-Date -f 'HH:mm:ss') + '  ' + $m
    try { Add-Content -LiteralPath $out -Value $line -ErrorAction SilentlyContinue } catch { }
    Write-Output $line
    try { (New-Object Net.WebClient).UploadString("$base/log?vm=p100", $line) } catch { }
}
function Hex([byte[]]$b) { if (-not $b) { return '' } ; return (($b | ForEach-Object { $_.ToString('x2') }) -join '') }

if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$VER = 'p100-v1'
$lock = Join-Path $dir '_p100.lock'
if (Test-Path -LiteralPath $lock) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds
    if ($age -lt 45) { L ("skip $VER lock age=" + [int]$age) ; exit 0 }
}
Set-Content -LiteralPath $lock -Value (Get-Date -f 'HH:mm:ss') -Encoding ascii
L ("=== p100 guest-entry version=$VER")

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P100 {
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

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$up = 0
if ($os) { $up = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds }
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$rammb = 0
if ($cs) { $rammb = [int]($cs.TotalPhysicalMemory / 1MB) }
L ("=== p100 start {0} up={1}s ram={2}MB" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss'), $up, $rammb)

$canary = New-Object byte[] $PAGE
for ($i = 0; $i -lt $PAGE; $i++) { $canary[$i] = [byte]($i -band 0xFF) }

# 1 MiB .. 4 GiB, doubling then filling the 1 MiB grid, so a boundary is bracketed rather than hit.
$sweep = @(0x100000, 0x200000, 0x300000, 0x400000, 0x500000, 0x800000, 0x1000000, 0x2000000,
           0x4000000, 0x8000000, 0x10000000, 0x20000000, 0x40000000)
$okn = 0; $badn = 0; $firstbad = 0; $lastok = 0

foreach ($pa in $sweep) {
    $h = [IntPtr]::Zero
    $try = [P100]::CreateFileW('\\.\GIOV3', 0xC0000000L, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($try -and $try.ToInt64() -ne -1) { $h = $try } else { L ("  pa=0x{0:x} open FAILED" -f $pa) ; continue }

    $p = [P100]::VirtualAlloc([IntPtr]::Zero, $PAGE, 0x3000, 0x04)
    [Runtime.InteropServices.Marshal]::Copy($canary, 0, $p, $PAGE)
    [P100]::VirtualLock($p, $PAGE) | Out-Null

    $ib = New-Object byte[] 24
    [Array]::Copy([BitConverter]::GetBytes([uint64]$pa), 0, $ib, 0, 8)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$PAGE), 0, $ib, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint64]$p.ToInt64()), 0, $ib, 16, 8)
    L ("BEFORE read pa=0x{0:x} dst=0x{1:x}" -f $pa, $p.ToInt64())
    $ob = New-Object byte[] $PAGE
    $got = [uint32]0
    $ok = [P100]::DeviceIoControl($h, $IOCTL_READ, $ib, [uint32]$ib.Length, $ob, [uint32]$ob.Length, [ref]$got, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [P100]::CloseHandle($h) | Out-Null

    $back = New-Object byte[] $PAGE
    [Runtime.InteropServices.Marshal]::Copy($p, $back, 0, $PAGE)
    $d = 0
    for ($i = 0; $i -lt $PAGE; $i++) { if ($back[$i] -ne $canary[$i]) { $d++ } }
    L ("  pa=0x{0:x} ok={1} err={2} diff={3} head={4}" -f $pa, [int]$ok, [int]$err, $d, (Hex ($back[0..15])))
    if ($ok -and $d -gt 0) { $okn++ ; $lastok = $pa } else { $badn++ ; if (-not $firstbad) { $firstbad = $pa } }
    [P100]::VirtualFree($p, 0, 0x8000) | Out-Null
    Start-Sleep -Milliseconds 120
}

L ("RESULT ok={0} bad={1} last_ok=0x{2:x} first_bad=0x{3:x}" -f $okn, $badn, $lastok, $firstbad)
if ($badn -eq 0) { L 'VERDICT: READ_ALL_OK' }
elseif ($okn -eq 0) { L 'VERDICT: READ_ALL_BAD' }
elseif ($firstbad -and $lastok -lt $firstbad -and $badn -eq ($sweep.Count - $okn)) { L 'VERDICT: READ_WINDOW_BOUNDED' }
else { L 'VERDICT: READ_SCATTERED_FAULTS' }
L ("VERDICT: P100_DONE " + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
