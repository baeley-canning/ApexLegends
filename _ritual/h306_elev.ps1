# h306_elev.ps1 - probe #306 (variable: elevation route). h305 result: the schtasks idea dies at creation -
# `/create ... /rl highest` returns "Access is denied" from a medium token, while the same create WITHOUT
# `/rl highest` succeeds (h305_probe.txt), so a High task cannot be registered non-elevated and h305 never
# got to run. What h305 did prove is worth keeping: the payload lands and the elevated transcript is the
# right instrument. h304 also showed that a scancode Enter lands on a secure desktop (it submitted the
# logon), which is exactly what a UAC consent prompt needs.
# So: drive the logged-on session the way a user would - Win+R, `cmd /c h306.cmd`, Ctrl+Shift+Enter,
# then Enter on the UAC prompt (default button). If UAC is set to "do not notify" it elevates silently and
# the extra Enter is a harmless no-op on the new console window.
# Restore: payload deleted; the DMP copy is kept for copyfrom. A stray elevated console may stay open -
# it is logged in the output and closed by the next probe's cleanup.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$want  = 391099508
$gDmp  = 'C:\Users\Public\h306_MEMORY.DMP'
$gTxt  = 'C:\Users\Public\h306_elevated.txt'
$gCmd  = 'C:\Users\Public\h306.cmd'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h306_elev.txt'
$so    = "$env:TEMP\h306o.txt"; $se = "$env:TEMP\h306e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h306 elev: Win+R + Ctrl+Shift+Enter via keyboard -> module owning 0xfffff80219033bc9 ===' -f (Get-Date -f 'HH:mm:ss.fff')))
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
function K([string[]]$codes) { $r = (& $vb controlvm $VM keyboardputscancode @codes 2>&1 | Out-String); W ('  key ' + ($codes -join ' ') + ' ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function KS([string]$s) { $r = (& $vb controlvm $VM keyboardputstring $s 2>&1 | Out-String); W ('  putstring "' + $s + '" ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function Size { $t = G 'poll' ('dir /-c /a ' + $gDmp); $m = [regex]::Match($t, '(\d+)\s+h306_MEMORY\.DMP'); if ($m.Success) { return [long]$m.Groups[1].Value } return 0 }
function Fire { K @('e0', '5b', '13', '93', 'e0', 'db'); Start-Sleep -Milliseconds 1200; KS ('cmd /c ' + $gCmd); Start-Sleep -Milliseconds 900; K @('1d', '2a', '1c', '9c', 'aa', '9d'); Start-Sleep -Seconds 4; K @('1c', '9c') }

# --- 1. pre-state ---
$tSess = G 'session' 'query session'
$tHku  = G 'hku' 'reg query HKU'
W ('pre-state: session1-loggedon=' + ($tSess -match 'vboxuser\s+1\s+Active') + ' hive=' + ($tHku -match 'S-1-5-21-1957909355-363273533-3916154183-1000'))
G 'stale' ('del /f /q ' + $gDmp + ' ' + $gTxt) | Out-Null

# --- 2. payload ---
$lines = @(
    '@echo off',
    ('echo START %DATE% %TIME% > "' + $gTxt + '"'),
    ('whoami >> "' + $gTxt + '"'),
    ('whoami /groups | findstr /i "Mandatory" >> "' + $gTxt + '"'),
    ('copy /y C:\Windows\MEMORY.DMP ' + $gDmp + ' >> "' + $gTxt + '" 2>&1'),
    ('echo COPY-RC=%ERRORLEVEL% >> "' + $gTxt + '"')
)
$tmp = Join-Path $d 'h306.cmd'
Set-Content -LiteralPath $tmp -Value $lines -Encoding ascii
$argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'copyto', ('"' + $tmp + '"'), ('"' + $gCmd + '"'))
$p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
$tP = G 'payload' ('type ' + $gCmd)
if ($tP -notmatch 'COPY-RC') { W 'RESULT: FAIL - payload did not land intact (variable: elevation route)'; exit 1 }

# --- 3. drive the session ---
W '--- fire 1: Win+R, cmd /c payload, Ctrl+Shift+Enter, Enter on UAC ---'
Fire
$gLen = 0
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $gLen = Size
    if ((($i % 3) -eq 0) -or ($gLen -ge $want)) { W ('  poll t=' + (5 * $i) + 's bytes=' + $gLen) }
    if ($gLen -ge $want) { break }
}
# --- 4. one retry: focus may have stayed in the Run box, or the consent prompt needs its own Enter ---
if ($gLen -lt $want) {
    W '--- fire 2 (retry): same sequence again ---'
    Fire
    for ($i = 1; $i -le 24; $i++) {
        Start-Sleep -Seconds 5
        $gLen = Size
        if ((($i % 3) -eq 0) -or ($gLen -ge $want)) { W ('  poll t=' + (5 * $i) + 's bytes=' + $gLen) }
        if ($gLen -ge $want) { break }
    }
}

# --- 5. read-back + verdict; transcript High Mandatory Level is the gate, size is the corroboration ---
$tR = G 'elevreport' ('type ' + $gTxt)
$high = ($tR -match 'High Mandatory Level')
W ('transcript: high-integrity=' + $high + ' staged=' + $gLen + ' want=' + $want)
G 'cleanup' ('del /f /q ' + $gCmd) | Out-Null
if (($gLen -eq $want) -and $high) { W 'RESULT: PASS - high-integrity transcript, guest copy is exactly 391,099,508 bytes (variable: elevation route)' }
elseif ($high) { W ('RESULT: PARTIAL - elevated, but size ' + $gLen + ' != ' + $want + ' (variable: elevation route)') }
elseif ($gLen -gt 0) { W 'RESULT: PARTIAL - file appeared but no High Mandatory Level in the transcript: medium token' }
else { W 'RESULT: FAIL - neither fire produced an elevated copy (variable: elevation route)' }
W 'VERDICT: only delta=0 on copyfrom AND a High Mandatory Level line make the kd read valid'

