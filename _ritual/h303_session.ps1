# h303_session.ps1 - probe #303 (variable: interactive-logon / hive-load state). Read-only, no mutation.
# h302 got --profile to work (USERPROFILE became C:\Users\vboxuser, the .cmd joined correctly) yet HKCU
# still answered "Access is denied" and the HKU\SID add answered "The parameter is incorrect". Both fit
# one cause: vboxuser has no loaded profile hive - the guest is sitting at the logon screen, so session 1
# exists ("Conn") but has no user. --profile then only sets USERPROFILE, it cannot load a hive.
# This probe records that state and whether the guest can log itself on, because auto-elevation needs a
# session whose HKCU actually exists. Nothing is written; the dump stays where it is.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$base  = 'guestcontrol ' + $VM
$auth  = '--username vboxuser --password vboxuser'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h303_session.txt'
$so    = "$env:TEMP\h303o.txt"; $se = "$env:TEMP\h303e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (('{0} === h303 session/hive state (variable: interactive logon) ===' -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

function G([string]$label, [string]$cmdline, [string]$optTail = '--profile', [int]$wait = 120000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = $base + ' ' + $auth + ' run ' + $optTail + ' --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 90000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 1. who is actually logged on, and is a shell or the logon UI running ---
G 'quser' 'query user' | Out-Null
G 'qsess' 'query session' | Out-Null
G 'explorer' 'tasklist /fi "imagename eq explorer.exe" /fo list' | Out-Null
G 'logonui' 'tasklist /fi "imagename eq LogonUI.exe" /fo list' | Out-Null
G 'sihost' 'tasklist /fi "imagename eq sihost.exe" /fo list' | Out-Null
G 'winlogon' 'tasklist /fi "imagename eq winlogon.exe" /fo list' | Out-Null

# --- 2. is the hive loaded? A locked NTUSER.DAT and an HKU entry both mean "logged on". ---
G 'ntuser' 'dir C:\Users\vboxuser\NTUSER.DAT* /a' | Out-Null
G 'hku' 'reg query HKU' | Out-Null
G 'shellfold' 'reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Desktop' | Out-Null
G 'volenv' 'reg query "HKCU\Volatile Environment"' | Out-Null

# --- 3. our own token: integrity now, with the profile flag in play ---
G 'groups' 'whoami /groups /fo list' | Out-Null

# --- 4. can the guest log itself on after a reset? (read-only read of the autologon values) ---
G 'wl_user' 'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName' | Out-Null
G 'wl_auto' 'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon' | Out-Null
G 'wl_dom'  'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName' | Out-Null
G 'wl_pw'   'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword' | Out-Null
G 'lastpw'  'reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v LastUsedUsername' | Out-Null
G 'sess_num' 'reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections' | Out-Null

# --- 5. verdict ---
$t = Get-Content -LiteralPath $out -Raw
$loggedOn = ($t -match '(?i)explorer\.exe\s+\d+') -and ($t -match '(?i)NTUSER\.DAT\s')
$hasShell  = ($t -match '(?i)image name:\s+explorer\.exe')
W ''
W ('explorer resident: ' + $hasShell)
W ('profile hive in use: ' + ($t -match '(?i)NTUSER\.DAT\s'))
W ('autologon configured: ' + ($t -match 'AutoAdminLogon\s+REG_SZ\s+1'))
if ($loggedOn) { W 'RESULT: PASS - a session with a loaded hive exists; HKCU auto-elevation is viable as designed' }
else { W 'RESULT: PARTIAL - no interactive logon (logon screen): HKCU has no hive to arm, so auto-elevation cannot work until someone logs on' }
W 'VERDICT: read quser/explorer/NTUSER.DAT above; if no session, the next step is a logon (autologon + VM reset), not another registry probe'
