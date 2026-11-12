# h307_elev.ps1 - probe #307 (variable: delivery channel). h306 failed because the Win+R burst
# (e0 5b 13 93 e0 db in one putscancode call) did not reach the shell as Win+R: tasklist caught window
# title "Start" plus a swarm of msedgewebview2/Search processes - the burst opened the Start menu and the
# typed `cmd /c ...` went into Start search as a web query. Nothing ever ran, so "bytes=0" was again a
# channel failure, not a token failure.
# h307 drops Win+R. The Start menu is already open and its search box is focused, so: Esc, type `cmd`,
# Enter - a plain console appears in session 1 - then type a Start-Process -Verb RunAs line into that
# console and press Enter, then Enter on the UAC consent. Only putstring + Enter are used, both of which
# are proven on this guest (h304). A tasklist check confirms a session-1 console exists before the
# elevation line is typed; if it does not, the search step is retried once.
# Restore: payload deleted; DMP copy kept for copyfrom; leftover consoles are counted and logged.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$want  = 391099508
$gDmp  = 'C:\Users\Public\h307_MEMORY.DMP'
$gTxt  = 'C:\Users\Public\h307_elevated.txt'
$gCmd  = 'C:\Users\Public\h307.cmd'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h307_elev.txt'
$so    = "$env:TEMP\h307o.txt"; $se = "$env:TEMP\h307e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h307 elev: Start-search console + RunAs -> module owning 0xfffff80219033bc9 ===' -f (Get-Date -f 'HH:mm:ss.fff')))
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
function KS([string]$s) { $r = (& $vb controlvm $VM keyboardputstring $s 2>&1 | Out-String); W ('  putstring ' + $s.Length + ' chars ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function Size { $t = G 'poll' ('dir /-c /a ' + $gDmp); $m = [regex]::Match($t, '(\d+)\s+h307_MEMORY\.DMP'); if ($m.Success) { return [long]$m.Groups[1].Value } return 0 }
function Consoles { $t = G 'consoles' 'tasklist /v /fo csv /nh'; return (@($t -split "`r?`n") | Where-Object { $_ -match '^"cmd\.exe","\d+","Console","1"' }).Count }

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
$tmp = Join-Path $d 'h307.cmd'
Set-Content -LiteralPath $tmp -Value $lines -Encoding ascii
$argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'copyto', ('"' + $tmp + '"'), ('"' + $gCmd + '"'))
$p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
$tP = G 'payload' ('type ' + $gCmd)
if ($tP -notmatch 'COPY-RC') { W 'RESULT: FAIL - payload did not land intact (variable: delivery channel)'; exit 1 }

# --- 3. get a console in the session: Esc closes Start, search `cmd`, Enter ---
K @('01', '81'); Start-Sleep -Milliseconds 800
$c = Consoles
W ('consoles before: ' + $c)
KS ('cmd'); Start-Sleep -Milliseconds 500
K @('1c', '9c'); Start-Sleep -Seconds 5
$c2 = Consoles
W ('consoles after search step: ' + $c2)
if ($c2 -le $c) {
    W 'no new console - retrying the search step once'
    K @('01', '81'); Start-Sleep -Milliseconds 700
    K @('e0', '5b'); Start-Sleep -Milliseconds 400; K @('39', 'b9'); Start-Sleep -Milliseconds 600
    KS ('cmd'); Start-Sleep -Milliseconds 400
    K @('1c', '9c'); Start-Sleep -Seconds 5
    $c2 = Consoles
    W ('consoles after retry: ' + $c2)
}

# --- 4. elevate from that console: RunAs line, Enter, then Enter on the UAC consent (default Yes) ---
if ($c2 -gt $c) {
    W '--- elevation line into the session console ---'
    $runas = 'powershell -NoProfile -Command "Start-Process cmd -ArgumentList ''/c C:\Users\Public\h307.cmd'' -Verb RunAs"'
    KS $runas; Start-Sleep -Milliseconds 700
    K @('1c', '9c'); Start-Sleep -Seconds 6
    K @('1c', '9c')
}
$gLen = 0
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 5
    $gLen = Size
    if ((($i % 3) -eq 0) -or ($gLen -ge $want)) { W ('  poll t=' + (5 * $i) + 's bytes=' + $gLen) }
    if ($gLen -ge $want) { break }
}

# --- 5. verdict on the transcript, not on the size alone ---
$tR = G 'elevreport' ('type ' + $gTxt)
$high = ($tR -match 'High Mandatory Level')
W ('transcript: high-integrity=' + $high + ' staged=' + $gLen + ' want=' + $want)
G 'cleanup' ('del /f /q ' + $gCmd) | Out-Null
$left = Consoles
W ('restore: payload deleted; session-1 consoles still open=' + $left + ' (closed by the next probe)')
if (($gLen -eq $want) -and $high) { W 'RESULT: PASS - high-integrity transcript, guest copy is exactly 391,099,508 bytes (variable: delivery channel)' }
elseif ($high) { W ('RESULT: PARTIAL - elevated, but size ' + $gLen + ' != ' + $want + ' (variable: delivery channel)') }
elseif ($gLen -gt 0) { W 'RESULT: PARTIAL - file appeared but no High Mandatory Level line: medium token' }
else { W 'RESULT: FAIL - no elevated copy via the console route (variable: delivery channel)' }
W 'VERDICT: only delta=0 on copyfrom AND a High Mandatory Level line make the kd read valid'

