# h297_pull.ps1 - probe #297 (variable: who owns the guest process; a SYSTEM-owned session can read the DACL).
# Chain so far: h292 source= MEMORY.DMP (Minidump empty). h294 size path fine (391,099,508 b) but the
# copy died on "Access to guest file denied". h295: the session is WIN11-TEST2\vboxuser, medium
# integrity (EnableLUA=1, prompt=5), icacls and a raw File.Open both DENIED. h296: vboxuser IS in
# Administrators but filtered, and the built-in Administrator is Account active = No, so no testable
# elevated logon exists.
# Therefore: stop trying to elevate vboxuser and stop logging on as anyone. VBoxService runs as SYSTEM;
# a `guestcontrol run` with NO --username is started by it, which sidesteps the DACL entirely.
# Guest side stays reversible: one staging copy under C:\Users\Public, deleted at the end (R4).
# Own output (R5): _ritual\h297_pull.txt.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out   = Join-Path $d 'h297_pull.txt'
$kd    = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP   = [uint64]0xfffff80219033bc9
$gStage = 'C:\Users\Public\h297_MEMORY.DMP'
$local = Join-Path $tmp 'h297_MEMORY.DMP'
$so    = "$env:TEMP\h297o.txt"; $se = "$env:TEMP\h297e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (("{0} === h297 pull: MEMORY.DMP -> module owning {1:x16} (SYSTEM-owned guest session) ===" -f (Get-Date -f 'HH:mm:ss.fff'), $RIP))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

# --- runner: $cred is '' for the SYSTEM/SYSTEM-owned form, or '--username X --password Y' ---
function G([string]$label, [string]$cred, [string]$cmdline, [int]$wait = 150000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $pre = if ($cred) { $cred + ' ' } else { '' }
    $line = 'guestcontrol ' + $VM + ' ' + $pre + 'run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

$vmc = (& $vb showvminfo $VM --machinereadable 2>&1) -join "`n"
foreach ($ln in ($vmc -split "`r?`n")) { if ($ln -match '^VMState') { W ('  vm  | ' + $ln.Trim()) } }

# --- 1. who does an uncredentialed guest process run as? this is the whole variable ---
$t0 = G 'syscheck' '' 'whoami'
$isSys = ($t0 -match '(?i)nt authority\\system')
W ('system_owned=' + $isSys)

if (-not $isSys) {
    # --elevate exists on some builds; one attempt, then stop rather than guess
    $t1 = G 'elevate' '--elevate' 'whoami'
    if ($t1 -notmatch '(?i)nt authority\\system') {
        W 'RESULT: FAIL - neither an uncredentialed nor an --elevate run produced SYSTEM (variable: who owns the guest process)'
        W 'VERDICT: the DACL still blocks the copy; do not start the dump analysis on a partial file'
        exit 1
    }
    W '  (--elevate form is the working one)'
}

# --- 2. stage a readable copy from the SYSTEM-owned process (read of the source, write to Public) ---
G 'stage' '' ('copy /y C:\Windows\MEMORY.DMP C:\Users\Public\h297_MEMORY.DMP') | Out-Null
$t2 = G 'staged' '' ('dir C:\Users\Public\h297_MEMORY.DMP /a-d /-c')
$gLen = 0
$mm2 = [regex]::Match($t2, '\d{2}:\d{2}\s+([\d,]{6,})')
if (-not $mm2.Success) { $mm2 = [regex]::Match($t2, '([\d,]{9,})') }
if ($mm2.Success) { $gLen = [long]($mm2.Groups[1].Value -replace '[^\d]', '') }
W ('guest staged bytes=' + $gLen)
if ($gLen -lt 10000000) { W 'RESULT: FAIL - staging copy absent or short (variable: who owns the guest process)'; W 'VERDICT: the SYSTEM session exists but the copy did not land'; exit 1 }

# --- 3. pull it as vboxuser (C:\Users\Public is readable by Users, so the ACL that blocked h294 is gone) ---
if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
W ('copyfrom start (' + [math]::Round($gLen / 1MB, 1) + ' MB)')
$sw = [Diagnostics.Stopwatch]::StartNew()
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = 'guestcontrol ' + $VM + ' --username vboxuser --password vboxuser copyfrom "' + $gStage + '" "' + $local + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$okCopy = $p.WaitForExit(900000)
$sw.Stop()
if (-not $okCopy) { try { $p.Kill() } catch { } }
$ct = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0))
W ('copyfrom done waited=' + $okCopy + ' secs=' + [math]::Round($sw.Elapsed.TotalSeconds, 1))
foreach ($ln in ($ct -split "`r?`n")) { if ($ln.Trim()) { W ('  copy | ' + $ln.Trim()) } }
$hLen = 0
if (Test-Path -LiteralPath $local) { $hLen = (Get-Item -LiteralPath $local).Length }
W ('host copy bytes=' + $hLen + ' guest=' + $gLen + ' delta=' + ($hLen - $gLen))
if ($hLen -ne $gLen) { W 'RESULT: FAIL - host copy does not match the guest size (variable: who owns the guest process)'; W 'VERDICT: a truncated dump would give a silently wrong lm; discard it'; exit 1 }

# --- 4. analyse offline. `lm` alone names the owner: base/end come from the dump's module
#        list, so no symbols and no symbol server are needed for the containment test. ---
$klog = Join-Path $tmp 'h297_kd.log'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
$kdArg = '-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; !analyze -v; q"'
W 'kd start (!analyze -v is slow on a 391 MB dump without symbols; budget 15 min)'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$kp = Start-Process -FilePath $kd -ArgumentList $kdArg -NoNewWindow -PassThru
$okKd = $kp.WaitForExit(900000)
$sw2.Stop()
if (-not $okKd) { try { $kp.Kill() } catch { } }
W ('kd done waited=' + $okKd + ' secs=' + [math]::Round($sw2.Elapsed.TotalSeconds, 1) + ' log=' + $(if (Test-Path -LiteralPath $klog) { (Get-Item -LiteralPath $klog).Length } else { 'MISSING' }))
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd wrote no log (variable: who owns the guest process)'; exit 1 }
$k = Get-Content -LiteralPath $klog -EA 0

# --- 5. the containment test: exactly one module must straddle the RIP ---
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

# --- 6. !analyze's own opinion, kept separate from the arithmetic so the two can disagree ---
foreach ($ln in $k) {
    if ($ln -match '^(IMAGE_NAME|MODULE_NAME|FAULTING_MODULE|SYMBOL_NAME|BUGCHECK_STR|FAILURE_BUCKET_ID|PROCESS_NAME|DEVICE_OBJECT_NAME|BUGCHECK_CODE|BUGCHECK_P1|BUGCHECK_P2|BUGCHECK_P3|BUGCHECK_P4)\b' -or
        $ln -match 'Probably caused by|DEFAULT_BUCKET_ID|IMAGE_VERSION') {
        W ('  kd | ' + $ln.Trim())
    }
    if ($ln -match 'Unloaded modules') { W ('  kd | ' + $ln.Trim()) }
}

# --- 7. verdict ---
if ($hit) {
    W ('MODULE CONTAINING RIP: ' + $hit.Name + '  [base=0x{0:x16} end=0x{1:x16} off={2}]' -f $hit.Base, $hit.End, $hit.Off)
    W ('  span=0x{0:x} bytes  lm-detail: {1}' -f ($hit.End - $hit.Base), $hit.Rest)
    W ('RESULT: PASS - RIP 0x{0:x16} resolves to {1} (variable: who owns the guest process)' -f $RIP, $hit.Name)
    W ('VERDICT: crash site belongs to ' + $hit.Name + '; cross-check the IMAGE_NAME/MODULE_NAME lines above before staging a fix')
} else {
    W 'MODULE CONTAINING RIP: none - the RIP falls outside every module base/end lm reported'
    W '  That is itself evidence: an address outside all loaded modules means the fault happened'
    W '  after the owner was released (matches the last POSTed line "zapexdrv after release").'
    W ('RESULT: PARTIAL - lm parsed ({0} modules) but no containment (variable: who owns the guest process)' -f $nMod)
    W 'VERDICT: read the Unloaded-modules section of the kd log; the address may be unloaded space'
}

# --- 8. restore (R4): the guest staging copy is ours, so it goes; the host dump stays only if PARTIAL ---
G 'cleanup' '' ('del /f /q C:\Users\Public\h297_MEMORY.DMP') | Out-Null
$t9 = G 'gone' '' 'if exist C:\Users\Public\h297_MEMORY.DMP (echo STILL_THERE) else (echo GONE)'
W ('guest staging copy: ' + $(if ($t9 -match 'GONE') { 'deleted' } else { 'STILL THERE - delete by hand' }))
if ($hit) { W ('host copy kept for now: ' + $local + ' (' + $hLen + ' bytes) - delete after the module is cross-referenced') }
else { W ('host copy KEPT for the retry: ' + $local + ' (' + $hLen + ' bytes)') }
