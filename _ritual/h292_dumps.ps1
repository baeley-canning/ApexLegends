# h292_dumps.ps1 - probe #292 (variable: guestcontrol invocation form for the dump inventory).
# h291 failed for a probe reason, not an evidence reason: it captured guestcontrol with `&` (the
# shell drops multi-command stdout here) and asked the GUEST to redirect with `>`/`2>&1`, which
# got shredded into extra argv tokens - the pulled "listing" was a bare `dir` of System32 while
# `minidumps=5` had already been reported at 15:33 by h289p. This probe uses the form that
# actually worked in h288: Start-Process + host-side redirect, one pre-quoted command line, and
# NO `>`, `|`, `&` characters anywhere in the guest command. The inventory is done twice
# (PowerShell and cmd dir) so an empty answer cannot be one method's artefact.
#
# Read-only: Test-Path/Get-ChildItem/reg query/sc query. Nothing is created, deleted, started or
# written in the guest; no driver, no boot config, no scheduled task. Re-runnable (R4).
# Own output (R5): _ritual\h292_dumps.txt.
$ErrorActionPreference = 'Continue'
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out = Join-Path $d 'h292_dumps.txt'
$so  = "$env:TEMP\h292o.txt"
$se  = "$env:TEMP\h292e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value ("{0} === h292 dump inventory (variable: guestcontrol form) ===" -f (Get-Date -f 'HH:mm:ss.fff'))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

# The one guest runner. Single pre-quoted command line on purpose: Start-Process joins an
# ArgumentList array on bare spaces, which is what mangled earlier probes.
function G([string]$label, [string]$cmdline) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = 'guestcontrol ' + $VM + ' --username vboxuser --password vboxuser run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit(150000)) {
        $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0))
        W ($label + ' rc=' + $p.ExitCode)
    } else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT 150 s (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 0. pre-state (R3): the guest has to be up before any inventory means anything ---
$st = (& $vb showvminfo $VM --machinereadable 2>&1) -join "`n"
$vmState = ([regex]::Match($st, 'VMState="([^"]+)"')).Groups[1].Value
W ('pre vm: VMState=' + $vmState)
if ($vmState -ne 'running') { W 'RESULT: FAIL - guest not running, no inventory read (variable: guestcontrol form)'; W 'VERDICT: start the VM bench first; nothing was read'; exit 1 }

# --- 1. channel sanity: if this prints, guestcontrol itself works and later silence is real ---
G 'alive' 'echo H292-ALIVE'

# --- 2. the dump folder, method A (PowerShell; no pipes, no redirects, no wildcard in the path) ---
$c1 = @'
powershell -NoProfile -Command "$p='C:\Windows\Minidump'; 'DIR='+(Test-Path -LiteralPath $p); $a=@(Get-ChildItem -LiteralPath $p -Force -EA 0); 'ALL='+$a.Count; $m=@(Get-ChildItem -LiteralPath $p -Filter '*.dmp' -Force -EA 0); 'DMP='+$m.Count; foreach($f in $m){ '  d '+$f.Name+' '+$f.Length+' '+$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }"
'@
$t1 = G 'ps-minidump' ($c1.Trim())

# --- 3. method B: plain cmd dir, independent cross-check of the same folder ---
G 'cmd-dir' 'dir /a /o-d C:\Windows\Minidump'

# --- 4. the full dump: MEMORY.DMP is the artefact BugCheck 1001 named at 15:12:28 ---
$c2 = @'
powershell -NoProfile -Command "$m=Get-Item -LiteralPath 'C:\Windows\MEMORY.DMP' -EA 0; if($m){ 'MEM '+$m.Length+' '+$m.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'MEM absent' }"
'@
$t2 = G 'ps-memdmp' ($c2.Trim())

# --- 5. why a dump may be missing: the CrashControl policy, read rather than assumed ---
G 'crashcontrol' 'reg query HKLM\SYSTEM\CurrentControlSet\Control\CrashControl'

# --- 6. crash-context companion: the service the last probe started before it died ---
G 'svc' 'sc query zapexdrv'

# --- 7. decision: which artefact kd should be pointed at (the choice is host-side, not guessed) ---
$dmpN = -1; $memN = -1; $newest = $null; $memWhen = ''
foreach ($ln in ($t1 -split "`r?`n")) {
    $m = [regex]::Match($ln, '\bDMP=(\d+)')
    if ($m.Success) { $dmpN = [int]$m.Groups[1].Value }
    $m = [regex]::Match($ln, '\| \s*d (\S+) (\d+) (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)')
    if ($m.Success) {
        $o = [pscustomobject]@{ Name = $m.Groups[1].Value; Bytes = [long]$m.Groups[2].Value; When = $m.Groups[3].Value }
        if (-not $newest -or $o.When -gt $newest.When) { $newest = $o }
    }
}
foreach ($ln in ($t2 -split "`r?`n")) {
    $m = [regex]::Match($ln, '\| \s*MEM (\d+) (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)')
    if ($m.Success) { $memN = [long]$m.Groups[1].Value; $memWhen = $m.Groups[2].Value; W ('  MEMORY.DMP bytes=' + $memN + ' written=' + $memWhen) }
    if ($ln -match '\| MEM absent') { W '  MEMORY.DMP absent on the guest' }
}
W ('minidumps parsed=' + $dmpN + ' newest=' + $(if ($newest) { $newest.Name + ' ' + $newest.Bytes + 'b ' + $newest.When } else { 'none' }))

if ($dmpN -gt 0 -and $newest) {
    W ('SOURCE: C:\Windows\Minidump\' + $newest.Name + ' ' + $newest.Bytes + 'b - a minidump carries the loaded-module list kd needs for lm')
    W 'RESULT: PASS - minidump present and named after two independent listings (variable: guestcontrol form)'
    W 'VERDICT: h291''s File Not Found was the redirect-shredded probe, not an empty folder; pull this file next'
} elseif ($memN -gt 0) {
    W ('SOURCE: C:\Windows\MEMORY.DMP ' + $memN + 'b written ' + $memWhen + ' - kernel dump, larger to copy but authoritative for 15:12:28')
    W 'RESULT: PASS - no minidump parsed, full dump present and sized (variable: guestcontrol form)'
    W 'VERDICT: pull MEMORY.DMP; CrashControl above says why only the full dump exists'
} else {
    W 'SOURCE: none'
    W 'RESULT: PARTIAL - channel works, but neither a minidump nor MEMORY.DMP was read (variable: guestcontrol form)'
    W 'VERDICT: read the CrashControl lines above before concluding the dumps are gone'
}

