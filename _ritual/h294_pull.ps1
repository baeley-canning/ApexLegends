# h294_pull.ps1 - probe #294 (variable: evidence source = C:\Windows\MEMORY.DMP, not a minidump).
# Re-run of h293, which FAILed on its own parse, not on the guest: h293 matched '| MEM (\d+)' against
# the captured stdout, but that pipe only exists in this log's rendering of a line, never in what
# guestcontrol returns - so a 391 MB dump that was present read back as 0 bytes. The match here is
# '|'-agnostic and still anchored on the digits.
# h292 settled the source question with two independent guest listings: C:\Windows\Minidump exists
# and is EMPTY (ALL=0, DMP=0), while C:\Windows\MEMORY.DMP is 391,099,508 b written 2026-11-06
# 15:12:20 - eight seconds before the BugCheck 1001 at 15:12:28 whose Arg3 is the faulting RIP
# 0xfffff80219033bc9. CrashControl says CrashDumpEnabled=0x7 (automatic/kernel dump) with
# Overwrite=1, which is exactly why one full dump exists and no minidump does.
#
# Guest side is read-only: one Get-Item + one copyfrom. No driver, no service, no boot config.
# Reversible by deleting the host copy (R4). Own output (R5): _ritual\h294_pull.txt.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$tmp   = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$out   = Join-Path $d 'h294_pull.txt'
$kd    = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$RIP   = 0xfffff80219033bc9
$local = Join-Path $tmp 'h294_MEMORY.DMP'
$so    = "$env:TEMP\h294o.txt"; $se = "$env:TEMP\h294e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value ("{0} === h294 pull: MEMORY.DMP -> module owning {1:x16} ===" -f (Get-Date -f 'HH:mm:ss.fff'), $RIP)
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

# Same runner form h292 proved: one pre-quoted command line, host-side redirect, no `>`/`|` in the
# guest command (a guest redirect is what shredded h291's listing into a bare dir of System32).
function G([string]$label, [string]$cmdline, [int]$wait = 150000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = 'guestcontrol ' + $VM + ' --username vboxuser --password vboxuser run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) {
        $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0))
        W ($label + ' rc=' + $p.ExitCode)
    } else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT ' + [int]($wait / 1000) + ' s (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 0. pre-state (R3) ---
$st = (& $vb showvminfo $VM --machinereadable 2>&1) -join "`n"
$vmState = ([regex]::Match($st, 'VMState="([^"]+)"')).Groups[1].Value
W ('pre vm: VMState=' + $vmState)
if ($vmState -ne 'running') { W 'RESULT: FAIL - guest not running, nothing pulled (variable: evidence source)'; W 'VERDICT: the dump must be read off a running guest'; exit 1 }
if (-not (Test-Path -LiteralPath $kd)) { W ('RESULT: FAIL - kd.exe missing at ' + $kd); exit 1 }

# --- 1. re-read the source on the guest, so the copy is bounded by a number, not a guess ---
$c1 = @'
powershell -NoProfile -Command "$m=Get-Item -LiteralPath 'C:\Windows\MEMORY.DMP' -EA 0; if($m){ 'MEM '+$m.Length+' '+$m.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'MEM absent' }"
'@
$t1 = G 'pre-memdmp' ($c1.Trim())
$gBytes = 0
$mm = [regex]::Match($t1, 'MEM (\d+)')
if ($mm.Success) { $gBytes = [long]$mm.Groups[1].Value }
W ('guest MEMORY.DMP bytes=' + $gBytes)
if ($gBytes -lt 10000000) { W 'RESULT: FAIL - guest MEMORY.DMP absent or too small to hold a kernel dump (variable: evidence source)'; W 'VERDICT: re-check h292 before pulling'; exit 1 }

# --- 2. copy it out (read-only on the guest). 391 MB over guestcontrol needs a real budget. ---
if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
W ('copyfrom start (' + [math]::Round($gBytes / 1MB, 1) + ' MB) -> ' + $local)
$sw = [Diagnostics.Stopwatch]::StartNew()
Remove-Item -LiteralPath $so, $se -Force -EA 0
$line = 'guestcontrol ' + $VM + ' --username vboxuser --password vboxuser copyfrom "C:\Windows\MEMORY.DMP" "' + $local + '"'
$p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
$okCopy = $p.WaitForExit(900000)
$sw.Stop()
if (-not $okCopy) { try { $p.Kill() } catch { } }
$ct = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0))
W ('copyfrom done waited=' + $okCopy + ' secs=' + [math]::Round($sw.Elapsed.TotalSeconds, 1))
foreach ($ln in ($ct -split "`r?`n")) { if ($ln.Trim()) { W ('  copy | ' + $ln.Trim()) } }
$hBytes = 0
if (Test-Path -LiteralPath $local) { $hBytes = (Get-Item -LiteralPath $local).Length }
W ('host copy bytes=' + $hBytes + ' expected=' + $gBytes + ' delta=' + ($hBytes - $gBytes))
if ($hBytes -lt 10000000) { W 'RESULT: FAIL - host copy missing or truncated (variable: evidence source)'; W 'VERDICT: retry the copyfrom before analysing anything'; exit 1 }


# --- 3. analyse offline. `lm` alone names the owner: base/end come from the dump's module
#        list, so no symbols and no symbol server are needed for the containment test. ---
$klog = Join-Path $tmp 'h294_kd.log'
if (Test-Path -LiteralPath $klog) { Remove-Item -LiteralPath $klog -Force }
$kdArg = '-z "' + $local + '" -logo "' + $klog + '" -c ".bugcheck; lm; !analyze -v; q"'
W 'kd start (!analyze -v is slow on a 391 MB dump without symbols; budget 15 min)'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
$kp = Start-Process -FilePath $kd -ArgumentList $kdArg -NoNewWindow -PassThru
$okKd = $kp.WaitForExit(900000)
$sw2.Stop()
if (-not $okKd) { try { $kp.Kill() } catch { } }
W ('kd done waited=' + $okKd + ' secs=' + [math]::Round($sw2.Elapsed.TotalSeconds, 1) + ' log=' + $(if (Test-Path -LiteralPath $klog) { (Get-Item -LiteralPath $klog).Length } else { 'MISSING' }))
if (-not (Test-Path -LiteralPath $klog)) { W 'RESULT: FAIL - kd wrote no log (variable: evidence source)'; exit 1 }
$k = Get-Content -LiteralPath $klog -EA 0

# --- 4. the containment test: exactly one module must straddle the RIP ---
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

# --- 5. !analyze's own opinion, kept separate from the arithmetic so the two can disagree ---
foreach ($ln in $k) {
    if ($ln -match '^(IMAGE_NAME|MODULE_NAME|FAULTING_MODULE|SYMBOL_NAME|BUGCHECK_STR|FAILURE_BUCKET_ID|PROCESS_NAME|DEVICE_OBJECT_NAME|BUGCHECK_CODE|BUGCHECK_P1|BUGCHECK_P2|BUGCHECK_P3|BUGCHECK_P4)\b' -or
        $ln -match 'Probably caused by|DEFAULT_BUCKET_ID|IMAGE_VERSION') {
        W ('  kd | ' + $ln.Trim())
    }
    if ($ln -match 'Unloaded modules') { W ('  kd | ' + $ln.Trim()) }
}

# --- 6. verdict ---
if ($hit) {
    W ('MODULE CONTAINING RIP: ' + $hit.Name + '  [base=0x{0:x16} end=0x{1:x16} off={2}]' -f $hit.Base, $hit.End, $hit.Off)
    W ('  span=0x{0:x} bytes  lm-detail: {1}' -f ($hit.End - $hit.Base), $hit.Rest)
    W ('RESULT: PASS - RIP 0x{0:x16} resolves to {1} (variable: evidence source = MEMORY.DMP)' -f $RIP, $hit.Name)
    W ('VERDICT: crash site belongs to ' + $hit.Name + '; cross-check the IMAGE_NAME/MODULE_NAME lines above before staging a fix')
} else {
    W 'MODULE CONTAINING RIP: none - the RIP falls outside every module base/end lm reported'
    W '  That is itself evidence: an address outside all loaded modules means the fault happened'
    W '  after the owner was released (matches the last POSTed line "zapexdrv after release").'
    W ('RESULT: PARTIAL - lm parsed ({0} modules) but no containment (variable: evidence source = MEMORY.DMP)' -f $nMod)
    W 'VERDICT: read the Unloaded-modules section of the kd log; the address may be unloaded space'
}

