# g329_readonly.ps1 -- guest payload for h329. Driver v14, READ-ONLY survival bench in Win11-Test2.
# Runs as vboxuser from C:\Users\Public\p37 (files pushed by h329_vmbench.ps1). Loads the pushed
# zapexdrv.sys the same way s2_load_v14.ps1 does on the host (DSE flip -> sc create/start -> DSE
# straight back to 0x16), then proves the ABI against a fresh notepad as ground truth:
#   acceptance = VERSION==14, BASE(np)==Get-Process truth, Read8 64-batch (61 valid + 3 out-of-window),
#   ReadBuf 64B @exeBase == ReadProcessMemory bytes, 1-byte Write round-trip on np PEB (restored).
# Then runs h328_vadbase.ps1 in-guest, then survival re-reads at +60 s and +300 s, then teardown
# (stop+delete svc, DSE restored to its pre value, np killed). No game required in the guest.
# Output: C:\Users\Public\p37\g329_readonly.out (pulled back by the vmbench wrapper).
$ErrorActionPreference = 'Continue'
$d   = 'C:\Users\Public\p37'
$out = Join-Path $d 'g329_readonly.out'
$sys = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$V14 = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
function W([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Add-Content -LiteralPath $out -Value $line; Write-Host $line }
Set-Content -LiteralPath $out -Value ('===== g329 readonly survival (guest) ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
# Fh/Fh16, not H/H16: builtin alias 'h' -> Get-History shadows a function named H (alias beats function).
function Fh([string]$p) { if (Test-Path -LiteralPath $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { return 'MISSING' } }
function Fh16([string]$p) { $h = Fh $p; if ($h.Length -ge 16) { return $h.Substring(0,16) } else { return $h } }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Dev {
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string p, uint a, uint s, IntPtr sa, uint d, uint fl, IntPtr t);
  [DllImport("kernel32", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint il, byte[] o, uint ol, out uint r, IntPtr ov);
  [DllImport("kernel32")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool inh, int pid);
  [DllImport("kernel32", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, IntPtr n, out IntPtr r);
}
public static class Vd {
  [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, byte[] buf, int len, out int ret);
  public static long PebOf(IntPtr h) {
    var pbi = new byte[48]; int rr;
    if (NtQueryInformationProcess(h, 0, pbi, 48, out rr) != 0) return 0;
    return BitConverter.ToInt64(pbi, 8);
  }
}
'@
$IO_VER    = [uint32](0x8A702004L)
$IO_READ8  = [uint32](0x8A702010L)
$IO_READBUF= [uint32](0x8A702014L)
$IO_WRITE  = [uint32](0x8A702018L)
$IO_BASE   = [uint32](0x8A70201CL)
function OpenDev {
    $h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32](0xC0000000L), 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { return [IntPtr]::Zero }
    return $h
}
function Put32([byte[]]$b, [int]$o, [uint32]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Put64([byte[]]$b, [int]$o, [uint64]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Io([IntPtr]$h, [uint32]$c, [byte[]]$b) {
    [uint32]$r = 0
    return [Dev]::DeviceIoControl($h, $c, $b, [uint32]$b.Length, $b, [uint32]$b.Length, [ref]$r, [IntPtr]::Zero)
}
function Rpm([IntPtr]$h, [long]$a, [int]$n) { $bb = New-Object byte[] $n; $rd = [IntPtr]::Zero; if ([Dev]::ReadProcessMemory($h, [IntPtr]$a, $bb, [IntPtr]$n, [ref]$rd)) { return $bb } else { return $null } }
function Same([byte[]]$a, [byte[]]$b, [int]$n) { for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }; return $true }

W ('whoami=' + (whoami) + ' os=' + [Environment]::OSVersion.Version.ToString() + ' ps=' + $PSVersionTable.PSVersion.ToString() + ' elevated=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
W ('PRE svc=[' + (SvcQ) + ']')
$o = Kdu @('-prv', '20', '-dse'); $preD = if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
W ('PRE dse=0x' + $(if ($preD) { $preD } else { 'UNREADABLE' }))
$src = Join-Path $d 'zapexdrv.sys'
$hSrc = Fh $src
W ('pushed zapexdrv.sys sha=' + (Fh16 $src) + ' len=' + (Get-Item -LiteralPath $src -EA 0).Length)
if ($hSrc -ne $V14) { W 'RESULT: GUEST-FAIL - pushed image is not the v14 build (expected 317E4A86..)'; W 'VERDICT: g329 FAIL (staging)'; exit 1 }
Copy-Item -LiteralPath $src -Destination $sys -Force
W ('staged System32 sha=' + (Fh16 $sys) + ' len=' + (Get-Item -LiteralPath $sys).Length)
if ((SvcQ) -match 'RUNNING') { & "$env:SystemRoot\system32\sc.exe" stop apexdrv 2>&1 | Out-Null; for ($i = 0; $i -lt 12 -and (SvcQ) -match 'RUNNING'; $i++) { Start-Sleep -Milliseconds 500 } }
& "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
for ($i = 0; $i -lt 12 -and (SvcQ) -notmatch 'does not exist'; $i++) { Start-Sleep -Milliseconds 400 }
if ($preD -notmatch '^0*0$' -or -not $preD) { W ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
& "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
& "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
Start-Sleep -Seconds 2
$q = SvcQ
W ('svc after start: ' + $q)
if ($q -notmatch 'RUNNING') {
    $rst = if ($preD) { $preD } else { '22' }
    W ('dse restore out=[' + (Kdu @('-prv', '20', '-dse', $rst)) + ']')
    W 'RESULT: GUEST-FAIL - apexdrv did not start in guest'
    W 'VERDICT: g329 FAIL (start)'
    exit 1
}
W ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']')
Start-Sleep -Milliseconds 400
$c2 = Kdu @('-prv', '20', '-dse', '22'); $six = if ($c2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
W ('dse final=0x' + $(if ($six) { $six } else { 'UNREADABLE' }))
$dseOk = ($six -match '^0*16$')
$hdev = OpenDev
$ver = -1
if ($hdev -eq [IntPtr]::Zero) { W 'device open FAILED' }
else { $v = New-Object byte[] 8; if (Io $hdev $IO_VER $v) { $ver = [int][BitConverter]::ToUInt32($v, 0) }; W ('driver version=' + $ver) }
$acc = $false; $s60 = $false; $s300 = $false; $h328ok = $false; $tear = $false; $npH = [IntPtr]::Zero; $npp = $null
try {
if ($hdev -eq [IntPtr]::Zero -or $ver -ne 14) {
    W ('no usable device (ver=' + $ver + ') - acceptance/survival skipped')
} else {
    $npp = Start-Process notepad -PassThru
    Start-Sleep -Seconds 2
    $npp = Get-Process -Id $npp.Id -EA 0
    if (-not $npp) { throw 'notepad did not stay up' }
    $truth = $npp.MainModule.BaseAddress.ToInt64()
    $npH = [Dev]::OpenProcess([uint32]0x1F0FFF, $false, $npp.Id)
    $pebNp = [Vd]::PebOf($npH)
    W ('notepad pid=' + $npp.Id + ' truthBase=0x' + $truth.ToString('X') + ' peb=0x' + $pebNp.ToString('X') + ' handle=0x' + $npH.ToString('X'))
    $q = New-Object byte[] 24; Put32 $q 0 ([uint32]$npp.Id)
    $okB = Io $hdev $IO_BASE $q
    $stB = [int][BitConverter]::ToInt32($q, 8); $srB = [int][BitConverter]::ToInt32($q, 12); $bb = [BitConverter]::ToUInt64($q, 16)
    $baseOK = ($stB -eq 0 -and $bb -eq [uint64]$truth -and ($srB -eq 1 -or $srB -eq 2))
    W ('ACCEPT BASE status=0x' + $stB.ToString('X8') + ' source=' + $srB + ' base=0x' + $bb.ToString('X') + ' truth=0x' + $truth.ToString('X') + ' ok=' + $baseOK)
    $own = Rpm $npH $truth 64
    $rb = New-Object byte[] 4116; Put32 $rb 0 ([uint32]$npp.Id); Put32 $rb 4 64; Put64 $rb 8 ([uint64]$truth)
    $okR = Io $hdev $IO_READBUF $rb
    $stR = [int][BitConverter]::ToInt32($rb, 16)
    $drvB = New-Object byte[] 64; [Array]::Copy($rb, 20, $drvB, 0, 64)
    $eq = ($own -ne $null -and (Same $drvB $own 64))
    $readbufOK = ($stR -eq 0 -and $eq)
    W ('ACCEPT READBUF64 status=0x' + $stR.ToString('X8') + ' ==RPMbytes=' + $eq + ' first4=' + ('{0:X2}{1:X2}{2:X2}{3:X2}' -f $drvB[0], $drvB[1], $drvB[2], $drvB[3]))
    $r8 = New-Object byte[] 1288; Put32 $r8 0 ([uint32]$npp.Id); Put32 $r8 4 64
    for ($i = 0; $i -lt 61; $i++) { Put64 $r8 (8 + $i * 8) ([uint64]($truth + $i * 0x800)) }
    Put64 $r8 496 ([uint64]0x1000); Put64 $r8 504 ([uint64]0x100000000); Put64 $r8 512 ([uint64]0x800000000000)
    $ok8 = Io $hdev $IO_READ8 $r8
    $okN = 0; $badN = 0
    for ($i = 0; $i -lt 64; $i++) { if ([int][BitConverter]::ToInt32($r8, 520 + $i * 4) -eq 0) { $okN++ } else { $badN++ } }
    $mz8 = ((([BitConverter]::ToUInt64($r8, 776)) -band 0xFFFF) -eq 0x5A4D)
    $read8OK = ($okN -eq 61 -and $badN -eq 3 -and $mz8)
    W ('ACCEPT READ8 batch64 ok=' + $okN + ' bad=' + $badN + ' firstValMZ=' + $mz8 + ' (valid=61 in-image, bad=0x1000/0x100000000/0x800000000000)')
    $origB = (Rpm $npH ($pebNp + 0x10) 1)
    if ($origB -eq $null) { $writeOK = $false; W 'ACCEPT WRITE: PEB unreachable via RPM' }
    else {
        $oB = [int]$origB[0]
        $wr = New-Object byte[] 4116; Put32 $wr 0 ([uint32]$npp.Id); Put32 $wr 4 1; Put64 $wr 8 ([uint64]($pebNp + 0x10)); $wr[20] = [byte]($oB -bxor 0x01)
        $okW = Io $hdev $IO_WRITE $wr; $stW = [int][BitConverter]::ToInt32($wr, 16)
        $afterB = (Rpm $npH ($pebNp + 0x10) 1)[0]
        $wr[20] = [byte]$oB
        $okW2 = Io $hdev $IO_WRITE $wr; $stW2 = [int][BitConverter]::ToInt32($wr, 16)
        $backB = (Rpm $npH ($pebNp + 0x10) 1)[0]
        $writeOK = ($stW -eq 0 -and $stW2 -eq 0 -and $afterB -eq ($oB -bxor 0x01) -and $backB -eq $oB)
        W ('ACCEPT WRITE peb+0x10 status=0x' + $stW.ToString('X8') + '/0x' + $stW2.ToString('X8') + ' xorVisible=' + ($afterB -eq ($oB -bxor 0x01)) + ' restored=' + ($backB -eq $oB) + ' orig=0x' + $oB.ToString('X2'))
    }
    $acc = ($baseOK -and $readbufOK -and $read8OK -and $writeOK)
    W ('RESULT: GUEST ACCEPTANCE ' + $(if ($acc) { 'PASS' } else { 'FAIL' }) + ' (v14 vs notepad ground truth; base=' + $baseOK + ' readbuf=' + $readbufOK + ' read8=' + $read8OK + ' write=' + $writeOK + ')')
    # --- h328 in-guest: resolver ground-truth probe (own out file) ---
    $h328ps = Join-Path $d 'h328_vadbase.ps1'
    W 'running h328_vadbase.ps1 in-guest ...'
    $hp = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $h328ps) -PassThru -Wait
    W ('h328 exit=' + $hp.ExitCode)
    $h328out = Get-Content -LiteralPath (Join-Path $d 'h328_vadbase.out') -EA 0
    foreach ($ln in $h328out) { if ($ln -match 'RESULT:|VERDICT:') { W ('h328| ' + $ln) } }
    $h328ok = ($hp.ExitCode -eq 0)
    # --- survival: read-only re-reads at +60s and +300s ---
    $t0 = Get-Date
    function Surv([string]$tag) {
        $alive = [bool](Get-Process -Id $npp.Id -EA 0)
        $q = New-Object byte[] 24; Put32 $q 0 ([uint32]$npp.Id)
        $okB = Io $hdev $IO_BASE $q
        $stB = [int][BitConverter]::ToInt32($q, 8); $bb = [BitConverter]::ToUInt64($q, 16)
        $rb = New-Object byte[] 4116; Put32 $rb 0 ([uint32]$npp.Id); Put32 $rb 4 64; Put64 $rb 8 ([uint64]$truth)
        $okR = Io $hdev $IO_READBUF $rb; $stR = [int][BitConverter]::ToInt32($rb, 16)
        $mzv = ($rb[20] -eq 0x4D -and $rb[21] -eq 0x5A)
        $svc = ((SvcQ) -match 'RUNNING')
        $v2 = New-Object byte[] 8; $okV = Io $hdev $IO_VER $v2
        $ver2 = if ($okV) { [int][BitConverter]::ToUInt32($v2, 0) } else { -1 }
        $pass = ($alive -and $stB -eq 0 -and $bb -eq [uint64]$truth -and $stR -eq 0 -and $mzv -and $svc -and $ver2 -eq 14)
        W ($tag + ': alive=' + $alive + ' baseStatus=0x' + $stB.ToString('X8') + ' baseEq=' + ($bb -eq [uint64]$truth) + ' readStatus=0x' + $stR.ToString('X8') + ' MZ=' + $mzv + ' svcRUNNING=' + $svc + ' version=' + $ver2 + ' => ' + $(if ($pass) { 'PASS' } else { 'FAIL' }))
        return $pass
    }
    while (((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Seconds 2 }
    $s60 = Surv '+60s'
    while (((Get-Date) - $t0).TotalSeconds -lt 300) { Start-Sleep -Seconds 5 }
    $s300 = Surv '+300s'
    W ('RESULT: SURVIVAL +60s=' + $s60 + ' +300s=' + $s300)
}
} catch { W ('EXCEPTION: ' + $_.Exception.Message) }
# --- teardown: svc stop+delete, DSE restored to pre value, np killed, handles closed ---
try { if ($hdev -ne [IntPtr]::Zero) { [void][Dev]::CloseHandle($hdev) } } catch { }
try { if ($npH -ne [IntPtr]::Zero) { [void][Dev]::CloseHandle($npH) } } catch { }
try { if ($npp) { Stop-Process -Id $npp.Id -Force -EA 0 } } catch { }
& "$env:SystemRoot\system32\sc.exe" stop apexdrv 2>&1 | Out-Null
for ($i = 0; $i -lt 12 -and (SvcQ) -match 'RUNNING'; $i++) { Start-Sleep -Milliseconds 500 }
& "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
for ($i = 0; $i -lt 12 -and (SvcQ) -notmatch 'does not exist'; $i++) { Start-Sleep -Milliseconds 400 }
$rst = if ($preD -match '^[0-9A-Fa-f]+$') { $preD } else { '22' }
W ('dse restore out=[' + (Kdu @('-prv', '20', '-dse', $rst)) + ']')
Start-Sleep -Milliseconds 400
$c3 = Kdu @('-prv', '20', '-dse'); $fin = if ($c3 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
$finN = if ($fin) { [int][Convert]::ToInt32($fin, 16) } else { -1 }
$rstN = [int][Convert]::ToInt32($rst, 16)
$tear = (((SvcQ) -match 'does not exist') -and ($finN -eq $rstN))
W ('teardown: svc=[' + (SvcQ) + '] dse=0x' + $(if ($fin) { $fin } else { 'UNREADABLE' }) + ' target=0x' + $rst + ' ok=' + $tear)
$parts = @()
if (-not $acc) { $parts += 'acceptance' }
if (-not $s60) { $parts += 'surv+60' }
if (-not $s300) { $parts += 'surv+300' }
if (-not $h328ok) { $parts += 'h328' }
if (-not $dseOk) { $parts += 'dse-back-to-0x16' }
if (-not $tear) { $parts += 'teardown' }
$final = if ($parts.Count -eq 0) { 'PASS' } else { 'FAIL' }
W ('VERDICT: g329 ' + $final + $(if ($parts.Count) { ' failParts=' + ($parts -join ',') } else { '' }) + ' - variable = v14 in guest, DSE back to 0x16, ABI vs notepad ground truth, read-only 300s survival, svc+driver torn down, dse restored to pre-state')
if ($final -eq 'PASS') { exit 0 } else { exit 1 }