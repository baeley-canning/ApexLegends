# h286_cur.ps1 - H286 = the v13 verdict-plumbing fixes found by the h283-h285 review: the runs
# measured fine but could not be SCORED. Driver ABI v13:
#   1. resultStatus is printed on the delivered path too (v11 carried it, but only the
#      failed-IOCTL branch showed it - every delivered run parsed status=-1).
#   2. The map stub writes a DONE magic (0x4871) into a 4th data slot right after storing the
#      entry's RAX (MapEntryFlag): "DllMain returned FALSE" and "DllMain never returned" are
#      different verdicts now, and a FALSE return no longer burns the 10 s poll. Stub layout
#      code 64 / data 32, proven on the host first (_ritual/h286_stubtest.ps1, TRUE and FALSE
#      entry returns, both OK) - the h278 rule.
#   3. MapStatus no longer sticks at the IMPORTS step after a clean pass: step=9 + unresolved=
#      means exactly "an import did not resolve"; step=0 means no step refused.
#   4. The 1 s echo array is path-sized (260, was 64) so a long path can no longer read back
#      truncated and score a false mismatch.
#   5. This harness: inject cap 90 s -> 180 s, entryFlag/unresolved parsed and gated, the step
#      table knows step 9, dse_verify is wired into the verdict (PASS requires it), and the
#      PASS text no longer prints relocs twice through the imports= typo.
# Payload, stub target, DSE handling and restore chain unchanged from h285: the control payload
# (apxprobe.dll into notepad) is what makes the plumbing fixes measurable on their own.
#
# --- h285 header follows, still true ---
# h285_cur.ps1 - H285 = the v12 fix of what h284 named. The step reporter worked and read step 4
# (section copy bounds); the cause is in the driver's local section type, which omitted the PE
# spec's 8-byte Name array so VirtualAddress/SizeOfRawData/PointerToRawData were each read 8 bytes
# early - the bounds test compared VirtualSize+VirtualAddress (0x200+0x1000) against a 2048-byte
# file. Name is back, offsets are 8/12/16/20. Nothing else changes.
#
# --- h284 header follows, still true ---
# h284_cur.ps1 - H284 = h283 plus the copy-back fix. h283 measured that METHOD_BUFFERED hands back
# an ALL-ZERO out block on a failed status (step=0 modules=0/0 resultStatus=0), so the step codes
# v10 added were unwritable over the wire. Driver ABI v11 completes IOCTL_APEXDRV_INJECT as
# STATUS_SUCCESS and carries the real NTSTATUS in ResultStatus, so the block survives and the rung
# can name the refusing line. Launcher unchanged except the ABI constant; payload, stub, target and
# restore chain identical to h283.
#
# --- h283 header follows, still true ---
# h283_cur.ps1 - H283 = h282 plus INSTRUMENTATION ONLY: the map path now reports WHICH step
# refused instead of one opaque 193, and the launcher prints the out block on a failed IOCTL. h282
# proved the 0x1000 read floor was not the cause (clean rebuild, still 193; every header predicate
# recomputed against the real file passes locally), so the next run has to name the line rather
# than have us re-derive the checks by hand. Driver ABI v10: MapStatus is a step number
# (1 read, 2 header, 3 pool, 4 copy, 5 alloc, 6 reloc, 7 write, 8 stub) and the NTSTATUS moved to
# ResultStatus. Payload, stub, target and restore chain are unchanged from h282.
#
# --- h282 header follows, still true ---
# h282_cur.ps1 - H282 = h281 with ONE variable: the driver's image read floor. h281 measured a
# clean INSTRUMENT failure (abi v9 handshake fine, targetinfo fine) but the INJECT IOCTL returned
# GetLastError=193 = ERROR_BAD_EXE_FORMAT before any map step: ApexdrvReadImageFile refused the
# file on `EndOfFile < 0x1000` and apxprobe.dll is 2048 bytes. The header validator below already
# used 0x100, so the product of the two checks was the bug, not the payload. Floor is now 0x100
# and the pin names the rebuilt image. Nothing else changes: same payload, same stub, same target.
#
# --- h281 header follows, still true ---
# h281_cur.ps1 - H281 = h280 with ONE variable: the payload is mapped by hand instead of being
# handed to a loader. h280 closed the loader question (LoadLibraryExW on a proven pointer still
# returned 87 twice), so no Ldr path is used any more: the driver reads the file, lays the
# headers and sections out at their RVAs, applies relocations, and the APC entry calls
# DllMain(imageBase, DLL_PROCESS_ATTACH, NULL) and stores its BOOL.
#
# The payload is apxprobe.dll ON PURPOSE: 2 sections, 0x3000 image, NO relocations, NO imports,
# NO TLS, no CRT, DllMain returns TRUE. Everything that could fail for an unrelated reason is
# absent, so this rung measures the copy-and-call machinery alone.
#   VERDICT IS entryResult, NOT the module count - a mapped image is never in the Ldr list, so
#   the module count staying 35 is expected here and is not a failure.
# RCX is compared against MapBase in this rung (map mode hands the image base to the routine),
# not against remoteBase. The path echo is kept because it still proves the read reached the
# target, but the path is no longer the argument.
# The stub bytes are proven on the host first (_ritual/h281_stubtest.ps1) - do the same for any
# future stub change, h278 paid a guest run to learn that.
#
# --- h280 header follows, still true ---
# h279 settled the plumbing: the stub executed (entered=0x4870), RCX arrived holding exactly
# remoteBase, the echo held the full path before and 1 s after - and LoadLibraryW on that pointer
# still returned NULL with LastError 87, the same value the empty-string h275 got. So the string
# and the argument path are proven and the API call itself is what fails.
#
# --- h279 header follows, still true ---
# h278 answered nothing: it came back entered=0x1E05C748, rcx=0x260D8948000048. Those are the
# stub's OWN CODE BYTES (48 C7 05 1E / 48 89 0D 26), not stamps - v6 wrote the absolute data
# offsets (30, 38) as RIP-relative displacements and read back at the stub base. Both stores had
# landed at +41/+56 in the zero-filled page instead of +30/+38. ABI v7 writes 19/20 and reads
# the data slots, layout unchanged.
#
# --- h278 header follows, still true ---
# Driver ABI v6 answers both: the stub's first instruction stamps magic 0x4870, its second
# stores RCX, then it jumps to the real LoadLibraryW. The driver reads both back 1 s later and
# the launcher prints stub=/entered=/rcx=/remoteBase=.
#
# Everything else is h277 unchanged (full path, DSE read-back first, both restore arms).
#
# --- h277 header follows, still true ---
# h276 proved the resolved LoadLibraryW address is right (GetProcAddress on that same kernelbase
# returns exactly the 0xFC5B0 the driver called), proved the remote buffer holds the requested
# string (echo_status=0x0, echo matches, still there 1 s later) and proved the APC fired.
#
# --- h276 header follows, still true ---
# v5 reports what the target BUFFER holds -
# StatusEchoRead + RemotePathEcho (read immediately after the write, must equal the requested
# path) and StatusEchoAfter/RemotePathEchoAfter - plus a second sample 1 s later
# (StatusReadResult2 / LoadLibraryLastError2 / ModuleCountAfter2).
#
# Second fix, not a variable: h275's restore ran `kdu -dse 6` WITHOUT -prv, so kdu fell back to
# NalDrv.sys, which this build refuses with 0xC0000603 (cert revoked). No write happened and the
# guest was left at DSE=0 with no service. Both restore arms now pass -prv $winner and are
# followed by an identical read to prove the value, and the run starts with a read-back of DSE
# so nothing below trusts DSE without dse_pre.
#
# --- h271 header follows, still true ---
# v4 resolves kernel32!LoadLibraryW INSIDE the target (PEB -> Ldr -> kernelbase export table)
# and reports what the call DID instead of reporting that an APC was delivered. Target is
# NOTEPAD on purpose: the NULL-return reproduces there, so EAAC is out of the picture and a
# failure is provably ours. Verdict comes from the module count / echo / LastError, never an
# exit code.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
# h310 host port: byte-identical to C:\p37vm\payload\cur_h289_live.ps1 except $base/$tag/lock
# name. Origin is localhost:8080 (C:\p37vm\server.ps1, PID 17972) instead of the guest's
# 10.0.2.2, so the SHA pin still validates the SAME image that faulted at 15:12:28 and the
# POST feed lands in C:\p37vm\guest-h310.log. $d and the target path are unchanged, so the run is
# one-variable comparable to the 15:12 crash.
$base = 'http://127.0.0.1:8080'
$d    = 'C:\Users\Public\p37'
$tag  = 'h310'
$done = "$d\h310.done"
$L    = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add(((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s)) }
function Post {
    # Two runs stalled inside this function and never reached the injection: the whole list was
    # re-written to a guest file AND POSTed on every call. Send the tail only, with a hard 6 s
    # deadline (Invoke-WebRequest rather than WebClient, whose default is 100 s), and write the
    # guest-side .out only when the RESULT is already in the list.
    $body = if ($L.Count -gt 120) { ('...' + ($L.Count - 120) + ' earlier lines not uploaded') + "`r`n" + (($L | Select-Object -Last 120) -join "`r`n") } else { $L -join "`r`n" }
    for ($k = 1; $k -le 2; $k++) {
        try {
            [void](Invoke-WebRequest -Uri "$base/log?vm=$tag" -Method Post -Body ("## $tag`r`n" + $body) -TimeoutSec 6 -UseBasicParsing -EA Stop)
            break
        } catch { Start-Sleep -Milliseconds 300 }
    }
    # Every line is prefixed with HH:mm:ss.fff, so the on-disk writer must NOT anchor: '^RESULT: '
    # never matched and no run ever left a .out file (noticed 19:35 while filing today's PASS).
    if (($L | Select-String 'RESULT: ') -or ($L | Select-String 'VERDICT: ')) {
        try { Set-Content -LiteralPath "$d\$tag.out" -Value ($L -join "`r`n") } catch { }
    }
}
md $d -Force | Out-Null
# one completion marker: the tick re-arms every minute and every replay would reload
# the driver and re-cycle DSE. Delete the marker to re-arm deliberately.
if (Test-Path $done) { exit 0 }
$lock = "$d\h310.lock"
$bootId = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.Ticks
# single-run lock: stamped with this boot, so a lock orphaned by a bugcheck is stale
# immediately after the reboot instead of blocking the chain for its whole window.
if (Test-Path $lock) {
    $old = @(Get-Content $lock -EA 0)
    if ($old.Count -ge 2) {
        $age = [int]((Get-Date) - [datetime]::FromFileTime([long]$old[1])).TotalMinutes
        if ([long]$old[0] -eq $bootId -and $age -lt 12) { exit 0 }
    }
}
Set-Content -LiteralPath $lock -Value ($bootId, (Get-Date).ToFileTime())
if (Test-Path "$d\$tag.out") {
    Copy-Item -LiteralPath "$d\$tag.out" -Destination ("$d\$tag.hist." + (Get-Date -f 'MMdd-HHmmss') + '.out') -Force -EA 0
}
function Done { Remove-Item -LiteralPath $lock -Force -EA 0 }
function RunExe([string]$exe, [string[]]$argv, [int]$capMs = 20000, [int]$maxLines = 20) {
    $q = ''
    foreach ($a in $argv) { if ($a -match '[\s"]') { $q += ' "' + ($a -replace '"', '\"') + '"' } else { $q += ' ' + $a } }
    W ('$ ' + (Split-Path $exe -Leaf) + $q)
    $rc = -999; $out = ''
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $q.Trim(); $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $d; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $tO = $p.StandardOutput.ReadToEndAsync(); $tE = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($capMs)) { W ('  TIMEOUT ' + $capMs + 'ms'); try { $p.Kill() } catch { }; try { [void]$p.WaitForExit(3000) } catch { } }
        else { try { [void]$p.WaitForExit(2000) } catch { } }
        try { $rc = $p.ExitCode } catch { }
        foreach ($t in $tO, $tE) { if ($t.Wait(2500) -and $t.IsCompleted) { try { $out += $t.Result } catch { } } else { W '  (stream did not close)' } }
    } catch { W ('  LAUNCH FAIL ' + $_.Exception.Message) }
    if ($out) { $out = $out -replace "`r`n", "`n" }
    W ('  exit=' + $rc)
    $i = 0
    foreach ($line in ($out -split "`n")) { if ($i -ge $maxLines) { W '  | ...'; break }; if ($line.Trim() -ne '') { W ('  | ' + $line.TrimEnd()) }; $i++ }
    $script:lastOut = $out
    return $rc
}
function Svc([string]$argline, [int]$capMs = 8000) { return RunExe "$env:SystemRoot\system32\sc.exe" ($argline -split ' ') $capMs 8 }
# slice: verbatim, untruncated copies of the lines this run exists for. The modules: line now
# carries lastError2=, both echoes and the three stub fields, so it is copied whole instead of
# through the 32-line cap - the stub numbers must never be truncated away.
function Slice([string]$out) {
    foreach ($line in ($out -split "`n")) {
        if ($line -match 'driver ABI v|targetinfo:|delivery:|modules:|echo=|echo_after=|stub=|entered=|rcx=|remoteBase=|map: base=|entryResult=|\[\+\] Kernel injection|\[-\] delivered|VERDICT') {
            W ('  > ' + $line.Trim())
        }
    }
}
# restore (R4): driver stopped and deleted BEFORE DSE goes back, so a stale object cannot wedge
# the next run; notepad and the Public copy go too. Identical second call = read-back against
# the value step 1 observed. Called from every path that mutated something.
function Restore {
    W 'STEP=restore'
    Svc 'stop zapexdrv' 8000 | Out-Null
    Svc 'delete zapexdrv' 8000 | Out-Null
    Svc 'delete apexdrv' 8000 | Out-Null
    Get-Process notepad, regedit, mmc -EA 0 | Stop-Process -Force -EA 0
    Remove-Item -LiteralPath "$env:SystemDrive\Users\Public\apexprobe.dll" -Force -EA 0
    if ($winner -lt 0 -or $dseRestore -eq '') {
        $script:dseVerify = 'SKIP'
        W 'dse_verify=SKIP no provider / no dse_pre (DSE untouched this run)'
    } else {
        RunExe $kdu @('-prv', "$winner", '-dse', "$dseRestore") 15000 3 | Out-Null
        W ('dse restore out=[' + (($script:lastOut -replace '\s+', ' ').Trim()) + ']')
        # read-back: a second identical call prints the value it found before writing again.
        RunExe $kdu @('-prv', "$winner", '-dse', "$dseRestore") 15000 3 | Out-Null
        $dseLine = ($script:lastOut -replace '\s+', ' ').Trim()
        $okDse = ($dsePreText -ne '' -and $dseLine -match ('value:\s*' + [regex]::Escape($dsePreText) + '\b'))
        $script:dseVerify = $(if ($okDse) { 'PASS' } else { 'FAIL' })
        W ('dse_verify=' + $script:dseVerify + $(if ($okDse) { '' } else { ' out=[' + $dseLine + ']' }))
    }
    W ('restore: svc=[' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist|FAILED' }) -join ' ') + '] notepad=' + @(Get-Process notepad -EA 0).Count)
}
W 'alive'
W ('bench build ' + (Get-CimInstance Win32_OperatingSystem).BuildNumber + ' boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm') + ' pid=' + $PID)
W ('pre svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim())
W ('pre minidumps=' + @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count + ' notepad=' + @(Get-Process notepad -EA 0).Count)
try { Add-MpPreference -ExclusionPath $d -ErrorAction Stop } catch { }
Post

function Fetch([string]$name, [string]$to, [int]$minLen) {
    for ($i = 1; $i -le 3; $i++) {
        try { (New-Object Net.WebClient).DownloadFile("$base/$name", $to) } catch { }
        if ((Test-Path $to) -and ((Get-Item $to).Length -ge $minLen)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    W ('FETCH FAIL ' + $name); return $false
}
$sys = "$d\zapexdrv.sys"; $exe = "$d\apex_launcher.exe"; $dll = "$d\apxprobe.dll"; $zdl = "$d\zapexcheat.dll"; $kdu = "$d\kdu.exe"
$driverAbi = 13
$wantPath  = 'C:\Users\Public\apxprobe.dll'    # the control payload: no relocs/imports/TLS
# ABI v13 image. The pin is the v10 stub-fix image (pool stub + separate page-rounded
# allocation size) that closes h310's 0x50: ZwAllocateVirtualMemory had been rounding the
# shared stubSize to 0x1000 and the write then copied 0x1000 bytes off a 0x96-byte kernel
# stack array. Built by tools\BuildDriver.ps1, host-proven stub layout in
# _ritual\h286_stubtest.ps1 (both verdict=OK).
$finger = 'E906CEE97B9927F41B0C212C6C4E0E2D4E1DD3F70E35345C36A0E3D62EC1CC7C'
$pinned = ($finger.Length -eq 64)
$missing = @()
if (-not (Fetch 'kdu.exe' $kdu 400000)) { $missing += 'kdu' }
if (-not (Fetch 'drv64.dll' "$d\drv64.dll" 1000000)) { $missing += 'drv64' }
if (-not (Fetch 'zapexdrv.sys' $sys 4000)) { $missing += 'sys' }
if (-not (Fetch 'apex_launcher.exe' $exe 300000)) { $missing += 'exe' }
if (-not (Fetch 'apxprobe.dll' $dll 1500)) { $missing += 'dll' }
if (-not (Fetch 'zapexcheat.dll' $zdl 200000)) { $missing += 'zdll' }
$h = if (Test-Path $sys) { (Get-FileHash $sys -Algorithm SHA256).Hash } else { 'none' }
W ('sha=' + $h.Substring(0, [Math]::Min(16, $h.Length)) + $(if (-not $pinned) { ' UNPINNED' } elseif ($h -eq $finger) { ' MATCH' } else { ' MISMATCH' }))
if ($missing -or ($pinned -and $h -ne $finger)) { W ('RESULT: FAIL fetch ' + ($missing -join ',')); Post; Done; exit 1 }
W ('launcher sha=' + (Get-FileHash $exe -Algorithm SHA256).Hash.Substring(0, 16) + ' dll=' + (Get-FileHash $dll -Algorithm SHA256).Hash.Substring(0, 16))
Copy-Item -LiteralPath $dll -Destination "$env:SystemDrive\Users\Public\apxprobe.dll" -Force -EA 0
Post

# --- DSE read-back FIRST: h275's restore faulted, so nothing below may ASSUME a DSE state.
# Read-only form (no value argument: kdu loads the provider and prints, writes nothing). Value
# is printed in HEX and -dse parses DECIMAL, so the text is kept for comparison and converted
# only for the write. Providers come from the csv with 22 last (prv 22 = WinRing0, its
# MmMapIoSpace(NULL) path bugchecked twice).
W 'STEP=dse-read'
$dsePreText = ''; $dseRestore = ''; $winner = -1
$script:dseVerify = 'UNSET'   # set by Restore (PASS/FAIL/SKIP); the final verdict requires PASS
RunExe $kdu @('-listcsv', "$d\kdu_list.csv") 20000 3 | Out-Null
$ids = @()
foreach ($row in (Get-Content "$d\kdu_list.csv" -EA 0)) {
    if ($row -match '^\s*"?(\d{1,3})') { $ids += [int]$matches[1] }
}
$ids = @($ids | Select-Object -Unique | Where-Object { $_ -ne 22 })
$ids += 22
$readIds = @(22) + @($ids | Where-Object { $_ -ne 22 } | Select-Object -First 3)
foreach ($id in $readIds) {
    RunExe $kdu @('-prv', "$id", '-dse') 20000 4 | Out-Null
    if ($script:lastOut -match 'value:\s*([0-9A-Fa-f]+)') {
        $dsePreText = $matches[1].ToUpper(); $dseRestore = [string]([Convert]::ToInt32($dsePreText, 16))
        W ('  read via prv ' + $id)
        break
    }
    W ('  read prv ' + $id + ' no value: [' + (($script:lastOut -replace '\s+', ' ').Trim()) + ']')
}
W ('dse_pre=' + $(if ($dsePreText -ne '') { '0x' + $dsePreText } else { 'UNREADABLE' }) + ' restore-target=' + $(if ($dseRestore -ne '') { $dseRestore } else { 'none' }) + ' (0 = left as found)')
Post
if ($dsePreText -eq '') {
    W 'RESULT: FAIL - variable: DSE read-back unavailable, state of the guest not trusted'
    W 'VERDICT: FAIL - no provider could read GvCiOptions; nothing mutated, nothing restored'
    Restore; Post; Done; exit 1
}

# kdu: the new image is unsigned, so DSE has to be off.
W 'STEP=dse'
$dseOn = $true
Svc 'delete zapexdrv' 8000 | Out-Null
Svc ('create zapexdrv type= kernel start= demand binPath= ' + $sys) 8000 | Out-Null
foreach ($id in ($ids | Select-Object -First 4)) {
    RunExe $kdu @('-prv', "$id", '-dse', '0') 20000 2 | Out-Null
    Svc 'start zapexdrv' 8000 | Out-Null
    $q = ((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -join ' ')
    if ($q -match 'RUNNING') { $dseOn = $false; $winner = $id; W ('  prv ' + $id + ' -> DSE off, driver RUNNING'); break }
    W ('  prv ' + $id + ' no: ' + (($script:lastOut -replace '\s+', ' ').Trim()))
    Svc 'delete zapexdrv' 8000 | Out-Null
    Svc ('create zapexdrv type= kernel start= demand binPath= ' + $sys) 8000 | Out-Null
}
if ($dseOn) {
    W 'RESULT: FAIL no provider landed DSE=0'
    W ('VERDICT: FAIL - DSE unchanged at 0x' + $dsePreText + ', driver never started')
    Restore; Post; Done; exit 1
}
Post

# --- the probe itself: a control target -------------------------------------
# host note h310: the inbox notepad.exe on build 26200 is a Store-app stub that hands off and
# exits, so the launcher reported "no thread found in PID" 48 ms in and never reached the mapper.
# The candidate list is tried in order and the run only continues on a LIVE target with threads;
# the chosen name is logged so the verdict states which process was actually mapped into.
W 'STEP=target'
Get-Process notepad, regedit, mmc -EA 0 | Stop-Process -Force -EA 0
$tp = 0; $tname = ''
foreach ($cand in 'notepad', 'regedit', 'mmc') {
    try { $np = Start-Process $cand -PassThru } catch { W ('  target ' + $cand + ' no: ' + $_.Exception.Message); continue }
    Start-Sleep -Seconds 2
    $alive = [bool](Get-Process -Id $np.Id -EA 0)
    $nthr = if ($alive) { @((Get-Process -Id $np.Id).Threads).Count } else { 0 }
    W ('  target ' + $cand + ' pid=' + $np.Id + ' alive=' + $alive + ' threads=' + $nthr)
    if ($alive -and $nthr -gt 0) { $tp = $np.Id; $tname = $cand; break }
}
if ($tp -eq 0) {
    W 'RESULT: FAIL - variable: no control target stayed alive (notepad store stub, regedit, mmc)'
    W 'VERDICT: FAIL - target selection, not the mapper; nothing injected'
    Restore; Post; Done; exit 1
}
W ('target=' + $tname + ' pid=' + $tp + ' (control process for the map)')
Post
W 'STEP=probe-kernel'
Svc 'delete zapexdrv' 8000 | Out-Null
Svc 'delete apexdrv' 8000 | Out-Null
# h273 answered the prefix question: BOTH forms (NT-prefixed and plain) fail with 2, so
# ToNtPath is innocent. What was left running is the DSE probe service "zapexdrv" - a
# SECOND instance of the same image. Its DriverEntry does IoCreateDevice(\Device\ApexDrv),
# which collides with the already-loaded instance and the SCM reports the failure as 2.
# So: stop and release the probe service first, then let the launcher own the only
# instance. (The device name is per image, not per service name.)
W 'STEP=release'
Svc 'stop zapexdrv' 8000 | Out-Null
Svc 'delete zapexdrv' 8000 | Out-Null
W ('  zapexdrv after release: [' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist|FAILED' }) -join ' ') + ']')
Post
W 'STEP=probe-kernel (skipped: six h285 runs all stopped inside it, see header)'
# the ACG probe is not this rung's variable and it already answered its question; the tick was
# re-running the script because the probe never returned, so it is dropped from h285's path.
W 'STEP=inject-kernel'
# v13: 180 s cap. Worst case is 6 undelivered threads (3 s fire poll each) + the delivering
# thread (0.2 + 0.8 s windows + up to 10 s entry poll) ~ 32 s, but the 90 s cap of h285 left
# no headroom for a slow guest and the runs died inside it; 2x worst case is the floor now.
$rcI = RunExe $exe @('--inject', '--method=kernel', '--pid', "$tp", '--driver', $sys, '--dll', $wantPath, '--manual-map', '--no-sticky') 180000 32
$injOut = $script:lastOut
W 'STEP=slice'
Slice $injOut
Post

# read-back (R3): the process must still be alive, the service state is recorded and
# the payload's own oracle file may only exist if DllMain actually ran.
Start-Sleep -Seconds 2
W ('post target alive=' + [bool](Get-Process -Id $tp -EA 0) + ' inject rc=' + $rcI)
W ('post svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED' }) -join ' | ').Trim())
$hits = 0
foreach ($g in @("$env:SystemDrive\Users\*\AppData\Local\QwenKern", "$env:SystemDrive\Windows\Temp\QwenKern", "$env:SystemDrive\Windows\System32\config\systemprofile\AppData\Local\QwenKern")) {
    foreach ($dir in (Get-ChildItem -Path $g -Directory -EA 0)) {
        foreach ($f in (Get-ChildItem -Path $dir.FullName -Filter ('*' + $tp + '*') -EA 0)) { W ('  ORACLE ' + $f.FullName); $hits++ }
    }
}
W ('oracle hits=' + $hits)

# verdict (R3): in MAP mode the verdict is MapEntryResult, NOT the module count - a mapped image
# is never in the Ldr list, so a flat 35/35/35 here is EXPECTED and is not a failure. What has to
# hold instead: an image base was written (MapBase != 0), the APC fired, the map stub executed
# (entered=0x4870), RCX arrived as that base, the entry RETURNED (v13 entryFlag=0x4871), no
# import is unresolved, and DllMain returned TRUE through the stub. RCX is compared against
# MapBase in this rung (h279 compared it against remoteBase). MapStatus is quoted when the map
# itself failed (step 1..9) or when step=9 names an unresolved import.
$abi = -1; $fired = -1; $echoStatus = -1; $echo = ''; $echoAfter = ''
$mBefore = -1; $mAfter = -1; $mAfter2 = -1; $le1 = -1; $le2 = -1
$stubBase = [uint64]0; $entered = -1; $stubRcx = [uint64]0; $remoteBase = [uint64]0; $exUsed = -1
$mapBase = [uint64]0; $mapResult = [uint64]0; $mapStatus = -1; $mapNt = -1; $mapRelocs = -1; $mapImports = -1; $mapTls = -1
$mapFlag = [uint64]0; $mapUnresolved = ''
$magic = 0x4870
foreach ($line in ($injOut -split "`n")) {
    if ($line -match 'driver ABI v(\d+)') { $abi = [int]$matches[1] }
    if ($line -match 'delivery:') {
        if ($line -match 'fired=(\d)') { $fired = [int]$matches[1] }
        if ($line -match 'lastError=(\d+)') { $le1 = [int]$matches[1] }
        if ($line -match '\bex=(\d)') { $exUsed = [int]$matches[1] }
    }
    # the echo and stub fields ride on the modules: line (v5/v6 print them after lastError2=)
    if ($line -match 'modules: before=(\d+) after=(\d+) after2=(\d+)') {
        $mBefore = [int]$matches[1]; $mAfter = [int]$matches[2]; $mAfter2 = [int]$matches[3]
    }
    if ($line -match 'echo_status=0x([0-9A-Fa-f]+)') { $echoStatus = [Convert]::ToInt64($matches[1], 16) }
    if ($line -match 'echo=\[([^\]]*)\]') { $echo = $matches[1] }
    if ($line -match 'echo_after=\[([^\]]*)\]') { $echoAfter = $matches[1] }
    if ($line -match 'lastError2=(\d+)') { $le2 = [int]$matches[1] }
    if ($line -match '\bstub=0x([0-9A-Fa-f]+)') { $stubBase = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match '\bentered=0x([0-9A-Fa-f]+)') { $entered = [Convert]::ToInt64($matches[1], 16) }
    if ($line -match '\brcx=0x([0-9A-Fa-f]+)') { $stubRcx = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match '\bremoteBase=0x([0-9A-Fa-f]+)') { $remoteBase = [Convert]::ToUInt64($matches[1], 16) }
    # the map: line carries the whole map verdict (v10 prints step=, not status=)
    if ($line -match 'map: base=0x([0-9A-Fa-f]+)') { $mapBase = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match 'step=(\d+)') { $mapStatus = [int]$matches[1] }
    if ($line -match 'resultStatus=0x([0-9A-Fa-f]+)') { $mapNt = [Convert]::ToInt64($matches[1], 16) }
    if ($line -match 'entryResult=0x([0-9A-Fa-f]+)') { $mapResult = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match 'entryFlag=0x([0-9A-Fa-f]+)') { $mapFlag = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match 'unresolved=\[([^\]]*)\]') { $mapUnresolved = $matches[1] }
    if ($line -match 'relocs=(\d+)') { $mapRelocs = [int]$matches[1] }
    if ($line -match 'imports=(\d+)') { $mapImports = [int]$matches[1] }
    if ($line -match 'tls=(\d+)') { $mapTls = [int]$matches[1] }
}
$echoOk = ($echo.Trim() -ieq $wantPath)
W ('parsed: abi=' + $abi + ' echo_ok=' + [int]$echoOk + ' echo_status=' + $echoStatus + ' echo_len=' + $echo.Length + ' echo_after=[' + $echoAfter + '] fired=' + $fired + ' modules=' + $mBefore + '/' + $mAfter + '/' + $mAfter2 + ' (flat is fine here)')
W ('stub: base=0x' + $stubBase.ToString('X') + ' entered=' + $(if ($entered -lt 0) { 'unparsed' } else { '0x' + $entered.ToString('X') }) + ' rcx=0x' + $stubRcx.ToString('X'))
W ('map: base=0x' + $mapBase.ToString('X') + ' step=' + $mapStatus + ' resultStatus=' + $mapNt + ' entryResult=0x' + $mapResult.ToString('X') + ' entryFlag=0x' + $mapFlag.ToString('X') + ' relocs=' + $mapRelocs + ' imports=' + $mapImports + ' tls=' + $mapTls + ' unresolved=[' + $mapUnresolved + ']')
$loaded = ($mBefore -ge 0 -and (($mAfter -gt $mBefore) -or ($mAfter2 -gt $mBefore)))
$rcxOk  = ($mapBase -ne 0 -and $stubRcx -eq $mapBase)
# unsigned subtraction throws on a negative result in 5.1, so the sign is decided first
$delta   = if ($mapBase -eq 0) { 'n/a' } elseif ($stubRcx -ge $mapBase) { '0x' + ($stubRcx - $mapBase).ToString('X') } else { '-0x' + ($mapBase - $stubRcx).ToString('X') }

if ($abi -lt 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - no driver ABI handshake in the launcher output'
    $why = 'FAIL - launcher died before delivery (service/device), not the loader'
} elseif ($abi -lt $driverAbi) {
    $verdict = 'FAIL'
    $res = 'FAIL - driver ABI v' + $abi + ' < v' + $driverAbi + ', launcher refused before delivery'
    $why = 'FAIL - stale driver image, rebuild and reload apexdrv.sys'
} elseif ($mapBase -eq 0) {
    # FIRST after the handshake: a hard map failure also means no echo/stub fields exist, so the
    # echo branch below would otherwise blame the path copy for a mapper fault (h281/h282 did).
    # The step names the refusing line; resultStatus carries the NTSTATUS that step returned.
    $stepName = switch ($mapStatus) {
        1 { 'read/open of the file' }
        2 { 'PE header or section-table check' }
        3 { 'pool image allocation' }
        4 { 'section copy bounds' }
        5 { 'address-space allocation in the target' }
        6 { 'relocation pass' }
        7 { 'image write into the target' }
        8 { 'stub page alloc/write' }
        9 { 'import table (an import did not resolve)' }
        default { 'unreported step' }
    }
    $verdict = 'FAIL'
    $res = 'FAIL - map produced no image base at step ' + $mapStatus + ' (' + $stepName + ')'
    $why = 'FAIL - driver step ' + $mapStatus + ' = ' + $stepName + ', status=' + $mapNt + ' (0xC000007B = -1073741957 invalid image, 0xC0000017 = no memory); the APC path is not implicated'
} elseif ((-not $echoOk) -or $echoStatus -ne 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - map ok but path not in target (echo_status=' + $echoStatus + ' echo=' + $echo.Length + ')'
    $why = 'FAIL - copy/alloc, not the loader (echo=[' + $echo + '] after=[' + $echoAfter + '])'
} elseif ($fired -eq 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - path landed, APC never fired'
    $why = 'FAIL - thread choice, tid never returned alertable'
} elseif ($entered -lt 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - path landed, fired, but no entered= field in the output'
    $why = 'FAIL - launcher/driver ABI mix-up, stub fields missing (abi=' + $abi + ')'
} elseif ($stubBase -eq 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - path landed, fired, but no stub page (stub=0x0)'
    $why = 'FAIL - stub alloc/write failed inside the driver; unknown=unmeasured'
} elseif ($entered -eq 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - stub queued and fired=1, but entered=0'
    $why = 'FAIL - NO user-mode code ran: the APC routine did not execute (delivery/thread, not the mapper)'
} elseif ($entered -ne $magic) {
    $verdict = 'FAIL'
    $res = 'FAIL - widened map stub layout regressed: stamp 0x' + $entered.ToString('X') + ' (want 0x4870)'
    $why = 'FAIL - conclude NOTHING about the mapper from this run; hex-dump the stub page 0x' + $stubBase.ToString('X') + ' (0..96), rcx=0x' + $stubRcx.ToString('X')
} elseif ($mapBase -eq 0) {
    # unreachable when the block above already caught it; kept so the chain stays readable if the
    # branch is ever moved again.
    $verdict = 'FAIL'
    $res = 'FAIL - map produced no image base at step ' + $mapStatus
    $why = 'FAIL - driver step ' + $mapStatus + ', status=' + $mapNt
} elseif (-not $rcxOk) {
    $verdict = 'FAIL'
    $res = 'FAIL - stub entered, but rcx=0x' + $stubRcx.ToString('X') + ' != mapBase=0x' + $mapBase.ToString('X')
    $why = 'FAIL - OUR argument plumbing: RCX did not receive the mapped base (delta=' + $delta + ')'
} elseif ($mapFlag -eq 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - stub entered on the right base, but the entry never returned (entryFlag=0 after the 10 s poll)'
    $why = 'FAIL - DllMain did not COME BACK (hung or crashed inside the payload init), not "returned FALSE": the v13 DONE flag was never stamped'
} elseif ($mapUnresolved -ne '') {
    $verdict = 'FAIL'
    $res = 'FAIL - an import did not resolve: [' + $mapUnresolved + '] (driver step 9)'
    $why = 'FAIL - mapped, entered and returned, but an import is unresolved so the payload init cannot be trusted; the delivery path is fine'
} elseif ($mapResult -ne 1) {
    # BOOL: DllMain returns TRUE = 1. h310 measured entryResult=0x1 on a clean map and the probe
    # still scored FAIL, because this test used to be `-ne 0` - i.e. TRUE was read as FALSE.
    $verdict = 'FAIL'
    $res = 'FAIL - image mapped at 0x' + $mapBase.ToString('X') + ' but DllMain returned FALSE (entryResult=0x' + $mapResult.ToString('X') + ')'
    $why = 'FAIL - the mapping itself worked; the control payload rejected its own init (see the .dll log)'
} else {
    # base written, stub ran on the right argument, the entry RETURNED (flag) and returned TRUE.
    # Nothing else is needed: the image is deliberately absent from the Ldr list.
    $verdict = 'PASS'
    $res = 'PASS - manual map: image at 0x' + $mapBase.ToString('X') + ', DllMain returned TRUE through the map stub (entryFlag=0x' + $mapFlag.ToString('X') + ')'
    $why = 'MAP PASS - kernel-side PE map (relocs=' + $mapRelocs + ' imports=' + $mapImports + ' tls=' + $mapTls + '), APC + stub layout intact, entry executed, RETURNED (flag) and returned TRUE; no LoadLibrary involved'
}
if ($hits -gt 0) {
    if ($verdict -ne 'PASS') { $res = 'PASS - DllMain ran (oracle file)' }
    $verdict = 'PASS'; $why += ' (oracle file = DllMain ran)'
}
W ('RESULT: ' + $res)
W ('VERDICT: ' + $why)
Post

Restore
# v13: dse_verify is WIRED into the verdict, not just printed. An unverifiable restore means
# the guest was left in an unknown state, and a PASS the guest cannot vouch for is not a PASS -
# the whole lesson of the h283-h285 review.
if ($script:dseVerify -ne 'PASS') {
    if ($verdict -eq 'PASS') { $res = 'PASS on its own evidence, but dse_verify=' + $script:dseVerify + ' so the guest cannot be trusted' }
    $verdict = 'FAIL'
    $why += ' ; dse_verify=' + $script:dseVerify + ' - restore did not verify, guest state untrusted'
}
W ('dse_pre=0x' + $dsePreText + ' dse_verify=' + $script:dseVerify)
W ('RESULT: ' + $verdict + ' - variable: v13 verdict plumbing (resultStatus printed on delivery, entryFlag DONE magic separates returned-FALSE from never-returned, MapStatus reset after clean imports, path-sized echo_after). The driver maps ' + $wantPath + ' itself (kernel ZwCreateFile/ZwReadFile, header check, pool image, DIRECT64 relocation pass, one write) and the 64-byte map stub calls DllMain(base,1,NULL), storing RAX then the 0x4871 DONE flag; ex= and lastError= are informational only. Control payload = apxprobe.dll (no relocs, no imports, no TLS) into ' + $tname + ' (winner prv ' + $winner + '); this says nothing about apexcheat.dll, which brings imports, TLS and Guard CF')
Post
Set-Content -LiteralPath $done -Value $verdict
Done
