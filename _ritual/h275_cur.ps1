# h275_cur.ps1 - H272 = h271 rerun with ONE harness fix. h271's variable (driver ABI
# v4: target-side kernel32!LoadLibraryW resolution + module-count/LastError capture)
# never got measured: the launcher's OWN service "apexdrv" was left over from an older
# boot with a binPath that no longer exists, so StartService answered 2
# (ERROR_FILE_NOT_FOUND) before any injection. The fix is one line - delete "apexdrv"
# before the launcher runs, exactly like "zapexdrv" - and the variable is unchanged.
#
# --- h271 header follows, still true ---
# v4 resolves kernel32!LoadLibraryW INSIDE the target (PEB -> Ldr -> kernelbase
# export table) and reports what the call DID - module count before/after, the
# module that appeared, TEB LastErrorValue - instead of reporting that an APC was
# delivered. Target is NOTEPAD on purpose: the NULL-return reproduces there, so EAAC
# is out of the picture and a failure is provably ours.
# Verdict comes from the module-count delta + LastError; never from an exit code.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d    = 'C:\Users\Public\p37'
$tag  = 'h275'
$done = "$d\h275.done"
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
$lock = "$d\h275.lock"
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
$sys = "$d\zapexdrv.sys"; $exe = "$d\apex_launcher.exe"; $dll = "$d\apexcheat.dll"; $zdl = "$d\zapexcheat.dll"; $kdu = "$d\kdu.exe"
# ABI v4 image, pinned: a stale fetch would silently re-run the v3 path and the
# whole probe would measure the wrong thing.
$finger = 'EC366FD76C8A382EEDCB7E08F96E043BA27E100DC6D363E9394B0326998275A7'
$missing = @()
if (-not (Fetch 'kdu.exe' $kdu 400000)) { $missing += 'kdu' }
if (-not (Fetch 'drv64.dll' "$d\drv64.dll" 1000000)) { $missing += 'drv64' }
if (-not (Fetch 'zapexdrv.sys' $sys 4000)) { $missing += 'sys' }
if (-not (Fetch 'apex_launcher.exe' $exe 300000)) { $missing += 'exe' }
if (-not (Fetch 'apexcheat.dll' $dll 200000)) { $missing += 'dll' }
if (-not (Fetch 'zapexcheat.dll' $zdl 200000)) { $missing += 'zdll' }
$h = if (Test-Path $sys) { (Get-FileHash $sys -Algorithm SHA256).Hash } else { 'none' }
W ('sha=' + $h.Substring(0, [Math]::Min(16, $h.Length)) + $(if ($h -eq $finger) { ' MATCH' } else { ' MISMATCH' }))
if ($missing -or $h -ne $finger) { W ('RESULT: FAIL fetch ' + ($missing -join ',')); Post; Done; exit 1 }
W ('launcher sha=' + (Get-FileHash $exe -Algorithm SHA256).Hash.Substring(0, 16) + ' dll=' + (Get-FileHash $dll -Algorithm SHA256).Hash.Substring(0, 16))
Copy-Item -LiteralPath $dll -Destination "$env:SystemDrive\Users\Public\apexcheat.dll" -Force -EA 0
Post

# kdu: the new image is unsigned, so DSE has to be off. Providers come from the csv
# with 22 last (prv 22 = WinRing0, its MmMapIoSpace(NULL) path bugchecked twice).
W 'STEP=dse'
RunExe $kdu @('-listcsv', "$d\kdu_list.csv") 20000 3 | Out-Null
$ids = @()
foreach ($row in (Get-Content "$d\kdu_list.csv" -EA 0)) {
    if ($row -match '^\s*"?(\d{1,3})') { $ids += [int]$matches[1] }
}
$ids = @($ids | Select-Object -Unique | Where-Object { $_ -ne 22 })
$ids += 22
$dseOn = $true; $winner = 0
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
    RunExe $kdu @('-dse', '6') 15000 2 | Out-Null
    Post; Done; exit 1
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
$rcI = RunExe $exe @('--inject', '--method=kernel', '--pid', "$tp", '--driver', $sys, '--no-sticky') 90000 32
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

# verdict: the driver's own module-count delta and LastError are the only things that
# can say PASS - an rc of 0 was already printed while the call returned NULL.
$verdict = 'UNKNOWN'; $reason = ''
foreach ($line in ($script:lastOut -split "`n")) {
    if ($line -match 'modules: before=(\d+) after=(\d+)') {
        $b = [int]$matches[1]; $a = [int]$matches[2]
        if ($a -gt $b) { $verdict = 'PASS'; $reason = 'module appeared (' + $b + '->' + $a + ')' }
        else { $verdict = 'FAIL'; $reason = 'no module (' + $b + '->' + $a + ')' }
    }
    if ($line -match 'lastError=(\d+)') { $reason += ' lastError=' + $matches[1] }
    if ($line -match 'bases_differ=(\d)') { $reason += ' bases_differ=' + $matches[1] }
    if ($line -match 'resolve_path=(\d)') { $reason += ' resolve_path=' + $matches[1] }
}
if ($hits -gt 0) { $verdict = 'PASS'; $reason += ' (oracle file = DllMain ran)' }
W ('VERDICT: ' + $verdict + ' - ' + $reason.Trim())
Post

# --- restore (R4): driver stopped and deleted BEFORE DSE goes back. Service first,
# so a stale object cannot wedge the next run; notepad and the Public copy go too.
W 'STEP=restore'
Svc 'stop zapexdrv' 8000 | Out-Null
Svc 'delete zapexdrv' 8000 | Out-Null
Svc 'delete apexdrv' 8000 | Out-Null
Get-Process notepad -EA 0 | Stop-Process -Force -EA 0
RunExe $kdu @('-dse', '6') 15000 3 | Out-Null
W ('dse restore out=[' + (($script:lastOut -replace '\s+', ' ').Trim()) + ']')
W ('restore: svc=[' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist|FAILED' }) -join ' ') + '] notepad=' + @(Get-Process notepad -EA 0).Count)
Remove-Item -LiteralPath "$env:SystemDrive\Users\Public\apexcheat.dll" -Force -EA 0
W ('RESULT: ' + $verdict + ' - variable: driver ABI v4 (target-side resolve + result capture), target notepad, winner prv ' + $winner)
Post
Set-Content -LiteralPath $done -Value $verdict
Done
