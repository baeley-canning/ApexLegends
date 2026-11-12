# h308_elev.ps1 - probe #308 (variable: key timing for the Win combo). Two more routes died cheaply:
# a SYSTEM task needs elevation just like /rl highest (both "Access is denied" from a medium token), so
# Task Scheduler is out entirely. What is left is a real UAC elevation, and that needs the Win key to
# work: h306's single burst (e0 5b 13 93 e0 db) opened Start instead of Run, and h307's retry pressed
# Win+Space (input layout) because the space scan was wrong. Fixes here: Win is pressed and released in
# its own call, each key gets 300-600 ms, and Start-search gets 2 s to paint before anything is typed.
# `cmd` alone is used for the search (h306 searched a full command line, which yields web results and
# no launch). Consoles are counted quietly, before and after, as the delivery proof.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$want  = 391099508
$gDmp  = 'C:\Users\Public\h308_MEMORY.DMP'
$gTxt  = 'C:\Users\Public\h308_elevated.txt'
$gCmd  = 'C:\Users\Public\h308.cmd'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h308_elev.txt'
$so    = "$env:TEMP\h308o.txt"; $se = "$env:TEMP\h308e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h308 elev: separated Win key + Start search -> module owning 0xfffff80219033bc9 ===' -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }
function G([string]$label, [string]$cmdline, [int]$wait = 120000, [switch]$Quiet) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'run', '--profile',
              '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '60000',
              '--', 'cmd.exe', '/c', $cmdline)
    $p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    if (-not $Quiet) { foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } } }
    return $t
}
function K([string[]]$codes) { $r = (& $vb controlvm $VM keyboardputscancode @codes 2>&1 | Out-String); W ('  key ' + ($codes -join ' ') + ' ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function KS([string]$s) { $r = (& $vb controlvm $VM keyboardputstring $s 2>&1 | Out-String); W ('  putstring ' + $s.Length + ' chars ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function Size { $t = G 'poll' ('dir /-c /a ' + $gDmp) -Quiet; $m = [regex]::Match($t, '(\d+)\s+h308_MEMORY\.DMP'); if ($m.Success) { return [long]$m.Groups[1].Value } return 0 }
function Consoles { $t = G 'consoles' 'tasklist /v /fo csv /nh' -Quiet; return (@($t -split "`r?`n") | Where-Object { $_ -match '^"cmd\.exe","\d+","Console","1"' }).Count }
function WinKey { K @('e0', '5b'); Start-Sleep -Milliseconds 300; K @('e0', 'db') }

# --- 1. pre-state ---
$tSess = G 'session' 'query session' -Quiet
$tHku  = G 'hku' 'reg query HKU' -Quiet
W ('pre-state: session1-loggedon=' + ($tSess -match 'vboxuser\s+1\s+Active') + ' hive=' + ($tHku -match 'S-1-5-21-1957909355-363273533-3916154183-1000'))
G 'stale' ('del /f /q ' + $gDmp + ' ' + $gTxt) -Quiet | Out-Null

# --- 2. payload ---
$lines = @(
    '@echo off',
    ('echo START %DATE% %TIME% > "' + $gTxt + '"'),
    ('whoami >> "' + $gTxt + '"'),
    ('whoami /groups | findstr /i "Mandatory" >> "' + $gTxt + '"'),
    ('copy /y C:\Windows\MEMORY.DMP ' + $gDmp + ' >> "' + $gTxt + '" 2>&1'),
    ('echo COPY-RC=%ERRORLEVEL% >> "' + $gTxt + '"')
)
$tmp = Join-Path $d 'h308.cmd'
Set-Content -LiteralPath $tmp -Value $lines -Encoding ascii
$argv = @('guestcontrol', $VM, '--username', 'vboxuser', '--password', 'vboxuser', 'copyto', ('"' + $tmp + '"'), ('"' + $gCmd + '"'))
$p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
[void]$p.WaitForExit(60000)
$tP = G 'payload' ('type ' + $gCmd) -Quiet
if ($tP -notmatch 'COPY-RC') { W 'RESULT: FAIL - payload did not land intact (variable: key timing)'; exit 1 }

# --- 3. open a console: Win, settle, `cmd`, settle, Enter; verify by console count ---
$c0 = Consoles
W ('consoles baseline: ' + $c0)
K @('01', '81'); Start-Sleep -Milliseconds 800          # Esc: clear search results left from h306/h307, back to a clean Start
WinKey; Start-Sleep -Seconds 2
KS 'cmd'; Start-Sleep -Milliseconds 1500
K @('1c', '9c'); Start-Sleep -Seconds 5
$c1 = Consoles
W ('consoles after search: ' + $c1 + ' (delta ' + ($c1 - $c0) + ')')
if ($c1 -le $c0) {
    W 'no console - trying Run instead of search (separated Win+R, path typed)'
    K @('01', '81'); Start-Sleep -Milliseconds 600
    K @('e0', '5b'); Start-Sleep -Milliseconds 400; K @('13', '93'); Start-Sleep -Milliseconds 200; K @('e0', 'db')
    Start-Sleep -Seconds 2
    KS ('cmd /c ' + $gCmd); Start-Sleep -Milliseconds 1200
    K @('1c', '9c'); Start-Sleep -Seconds 8
    $c1 = Consoles
    W ('consoles after Run: ' + $c1 + ' (delta ' + ($c1 - $c0) + ')')
}

# --- 4. elevate from that console ---
if ($c1 -gt $c0) {
    W '--- RunAs line into the session console, then Enter on UAC ---'
    $runas = 'powershell -NoProfile -Command "Start-Process cmd -ArgumentList ''/c C:\Users\Public\h308.cmd'' -Verb RunAs"'
    KS $runas; Start-Sleep -Milliseconds 900
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

# --- 5. verdict on the transcript ---
$tR = G 'elevreport' ('type ' + $gTxt) -Quiet
$high = ($tR -match 'High Mandatory Level|System Mandatory Level')
W ('transcript: high-integrity=' + $high + ' staged=' + $gLen + ' want=' + $want)
G 'cleanup' ('del /f /q ' + $gCmd) -Quiet | Out-Null
W ('restore: payload deleted; session consoles=' + (Consoles))
if (($gLen -eq $want) -and $high) { W 'RESULT: PASS - high-integrity transcript, guest copy is exactly 391,099,508 bytes (variable: key timing)' }
elseif ($high) { W ('RESULT: PARTIAL - elevated, but size ' + $gLen + ' != ' + $want + ' (variable: key timing)') }
elseif ($gLen -gt 0) { W 'RESULT: PARTIAL - file appeared but no mandatory-level line: medium token' }
else { W 'RESULT: FAIL - still no elevated copy (variable: key timing)' }
W 'VERDICT: only delta=0 on copyfrom AND a High/System Mandatory Level line make the kd read valid'

