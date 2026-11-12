# h304_logon.ps1 - probe #304 (variable: sign-in attempt). Host-side input only, nothing mutated in the guest.
# h303 proved why every registry arm since h298 failed: nobody is logged on. Session 1 holds LogonUI, HKU has
# only .DEFAULT/S-1-5-19/20/18, vboxuser's NTUSER.DAT is on disk but NOT loaded, and AutoAdminLogon=1 has a
# DefaultUserName but no DefaultPassword - so the post-crash reboot parked at the sign-in screen instead of
# logging the user in. No hive, no HKCU, no auto-elevation, however the key is addressed.
# The VM is headless (no window, and screenshotpng is dead here: E_FAIL in TakeScreenShotToArray on monitor 0,
# E_INVALIDARG on monitor 1 because monitorcount=1 and the mode reports bpp 0), so this is keyboard-only, with
# the guest-control read-back as the only verdict (R3). STATE's proven sequence: lift the curtain, put the
# string with keyboardputstring (scancodes alone get dropped on the secure desktop), submit with 1c 9c.
# Attempt 2 presses Enter first, in case focus sits on the user tile instead of the password box.
# No reboot, no guest mutation: if both attempts fail the logon stays a human step, nothing is lost.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$base  = 'guestcontrol ' + $VM
$auth  = '--username vboxuser --password vboxuser'
$pw    = 'vboxuser'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h304_logon.txt'
$so    = "$env:TEMP\h304o.txt"; $se = "$env:TEMP\h304e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h304 logon (variable: sign-in attempt) ===' -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }
function K([string[]]$codes) { $r = (& $vb controlvm $VM keyboardputscancode @codes 2>&1 | Out-String); W ('  key ' + ($codes -join ' ') + ' ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function KS([string]$s) { $r = (& $vb controlvm $VM keyboardputstring $s 2>&1 | Out-String); W ('  putstring "' + $s + '" ' + $(if ($r.Trim()) { 'ERR:' + ($r -replace '\s+', ' ').Trim() } else { 'ok' })) }
function G([string]$label, [string]$cmdline, [int]$wait = 90000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = $base + ' ' + $auth + ' run --profile --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 60000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}
function LoggedOn { $t = G 'quser' 'query user'; return ($t -match '(?i)vboxuser') }

# --- 0. baseline: if someone is already signed in, do not type at all ---
if (LoggedOn) { W 'already signed in - nothing typed'; W 'RESULT: PASS (no action needed)'; exit 0 }
$t0 = G 'hku0' 'reg query HKU'
W ('baseline: hive loaded = ' + ($t0 -match 'S-1-5-21-1957909355'))

# --- attempt 1: curtain up, type the password, submit ---
W '--- attempt 1: esc, putstring, enter ---'
K @('01', '81'); Start-Sleep -Milliseconds 1200
KS $pw; Start-Sleep -Milliseconds 600
K @('1c', '9c')
$ok = $false
for ($i = 0; $i -lt 6; $i++) { Start-Sleep -Seconds 5; if (LoggedOn) { $ok = $true; break } W ('  wait ' + (($i + 1) * 5) + 's: not signed in yet') }

# --- attempt 2: focus was probably on the user tile - select it first, then type ---
if (-not $ok) {
    W '--- attempt 2: esc, enter (select tile), putstring, enter ---'
    K @('01', '81'); Start-Sleep -Milliseconds 1000
    K @('1c', '9c'); Start-Sleep -Milliseconds 2000
    KS $pw; Start-Sleep -Milliseconds 600
    K @('1c', '9c')
    for ($i = 0; $i -lt 6; $i++) { Start-Sleep -Seconds 5; if (LoggedOn) { $ok = $true; break } W ('  wait ' + (($i + 1) * 5) + 's: still not signed in') }
}

# --- read-back: the hive is the thing that matters, not the picture ---
$tH = G 'hku' 'reg query HKU'
$hive = ($tH -match 'S-1-5-21-1957909355-363273533-3916154183-1000')
G 'explorer' 'tasklist /fi "imagename eq explorer.exe" /fo list' | Out-Null
G 'sess' 'query session' | Out-Null
G 'ga' 'sc query VBoxService | findstr /i "STATE"' | Out-Null
W ''
W ('signed in: ' + $ok + ' / profile hive loaded: ' + $hive)
if ($ok -and $hive) { W 'RESULT: PASS - vboxuser session up, HKU<SID> loaded, HKCU is now armable (h302 can be re-run as-is)' }
elseif ($ok) { W 'RESULT: PARTIAL - signed in but the hive is still not under HKU: profile not loaded, treat as failure' }
else { W 'RESULT: FAIL - no sign-in from keyboard injection; next step is a manual logon at the VM console' }
W 'VERDICT: the hive line decides it - HKCU auto-elevation needs a loaded profile, not just a session'
