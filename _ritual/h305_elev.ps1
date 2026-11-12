# h305_elev.ps1 - probe #305 (variable: elevation trigger). h302 fixed the addressing (ARM-RC=0,
# DelegateExecute visible under HKU\<SID>, cross-hive read agreed) but nothing elevated ever ran:
# `start fodhelper.exe` from a session-0 guest-control process exited without firing the delegate
# ("cannot find the file specified" for the transcript, and its size poll was broken anyway - every
# elev script since h298 carries `for %A in (...)`, which cmd rejects as "was unexpected at this time"
# under the guestcontrol `run --` argument path, so "bytes=0" in h298-h302 was never a measurement).
# h304 changed the ground: vboxuser is now logged on in session 1 with the hive loaded. So the trigger
# is a scheduled task with `/rl highest /it` - an elevated run of the user's own interactive token,
# no UAC dialog, no delegate, no window station to guess at. The task writes its own transcript, and
# `whoami /groups` must show High Mandatory Level before the copy is worth anything.
# Reversible in the same script: the task is deleted and the payload removed; the DMP copy is kept
# for copyfrom. Size polling is `dir /-c` + regex (no `for`), so the number is real this time.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$want  = 391099508
$gDmp  = 'C:\Users\Public\h305_MEMORY.DMP'
$gTxt  = 'C:\Users\Public\h305_elevated.txt'
$gCmd  = 'C:\Users\Public\h305.cmd'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h305_elev.txt'
$so    = "$env:TEMP\h305o.txt"; $se = "$env:TEMP\h305e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h305 elev: schtasks /rl highest /it -> module owning 0xfffff80219033bc9 ===' -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }
function G([string]$label, [string]$cmdline, [int]$wait = 120000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'run', '--profile',
              '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '60000',
              '--', 'cmd.exe', '/c', $cmdline)
    $p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}
function Size { $t = G 'poll' ('dir /-c /a ' + $gDmp); $m = [regex]::Match($t, '(\d+)\s+h305_MEMORY\.DMP'); if ($m.Success) { return [long]$m.Groups[1].Value } return 0 }

# --- 1. pre-state (R3): session, hive, task absent, artefacts absent ---
$tSess = G 'session' 'query session'
$tHku  = G 'hku' 'reg query HKU'
$tTask = G 'task0' 'schtasks /query /tn h305 /fo list'
W ('pre-state: session1-loggedon=' + ($tSess -match 'vboxuser\s+1\s+Active') + ' hive=' + ($tHku -match 'S-1-5-21-1957909355-363273533-3916154183-1000') + ' task-exists=' + ($tTask -match 'h305'))
G 'stale' ('del /f /q ' + $gDmp + ' ' + $gTxt) | Out-Null

# --- 2. payload: transcript first, SoT for the token, then the copy ---
$lines = @(
    '@echo off',
    ('echo START %DATE% %TIME% > "' + $gTxt + '"'),
    ('whoami >> "' + $gTxt + '"'),
    ('whoami /groups | findstr /i "Mandatory" >> "' + $gTxt + '"'),
    ('copy /y C:\Windows\MEMORY.DMP ' + $gDmp + ' >> "' + $gTxt + '" 2>&1'),
    ('echo COPY-RC=%ERRORLEVEL% >> "' + $gTxt + '"')
)
$tmp = Join-Path $d 'h305.cmd'
Set-Content -LiteralPath $tmp -Value $lines -Encoding ascii
$argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'copyto', ('"' + $tmp + '"'), ('"' + $gCmd + '"'))
$p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
foreach ($ln in (((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) -split "`r?`n")) { if ($ln.Trim()) { W ('  copyto | ' + $ln.Trim()) } }
$tP = G 'payload' ('type ' + $gCmd)
if ($tP -notmatch 'COPY-RC') { W 'RESULT: FAIL - payload did not land intact (variable: elevation trigger)'; exit 1 }

# --- 3. create + run the elevated task. /it = the user's own interactive token, /rl highest = High IL ---
$tC = G 'create' ('schtasks /create /tn h305 /tr "' + $gCmd + '" /sc once /st 23:59 /ru vboxuser /rp vboxuser /rl highest /it /f')
if ($tC -notmatch '(?i)SUCCESS') { W 'RESULT: FAIL - task create refused (variable: elevation trigger)'; exit 1 }
G 'run' 'schtasks /run /tn h305' | Out-Null

# --- 4. poll the file, never the exit code (R3) ---
$gLen = 0
for ($i = 1; $i -le 36; $i++) {
    Start-Sleep -Seconds 5
    $gLen = Size
    if ((($i % 3) -eq 0) -or ($gLen -ge $want)) { W ('  poll t=' + (5 * $i) + 's bytes=' + $gLen) }
    if ($gLen -ge $want) { break }
    if (($gLen -eq 0) -and ($i -eq 5)) { $tQ = G 'taskq' 'schtasks /query /tn h305 /fo list /v'; if ($tQ -notmatch '(?i)Running|Ready') { W '  task is neither Ready nor Running - see taskq above' } }
}
$tR = G 'elevreport' ('type ' + $gTxt)
$high = ($tR -match 'High Mandatory Level')
W ('transcript: high-integrity=' + $high + ' staged=' + $gLen + ' want=' + $want)

# --- 5. restore: task gone, payload gone; the DMP copy stays for copyfrom ---
G 'cleanup' ('schtasks /delete /tn h305 /f & del /f /q ' + $gCmd) | Out-Null
$tTask2 = G 'task1' 'schtasks /query /tn h305 /fo list'
W ('restore: task removed=' + ($tTask2 -match 'cannot find|ERROR'))
if (($gLen -eq $want) -and $high) { W 'RESULT: PASS - high-integrity transcript, guest copy is exactly 391,099,508 bytes (variable: elevation trigger)' }
elseif ($high) { W ('RESULT: PARTIAL - elevated, but size ' + $gLen + ' != ' + $want + ' (variable: elevation trigger)') }
elseif ($gLen -gt 0) { W 'RESULT: PARTIAL - file appeared but the transcript shows no High Mandatory Level: medium token, bytes are not trustworthy' }
else { W 'RESULT: FAIL - the task ran but produced no copy (variable: elevation trigger)' }
W 'VERDICT: only delta=0 on copyfrom AND a High Mandatory Level line make the kd read valid'

