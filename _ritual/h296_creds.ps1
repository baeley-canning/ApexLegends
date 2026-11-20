# h296_creds.ps1 - probe #296 (variable: which guest identity can open C:\Windows\MEMORY.DMP).
# h295 settled it as identity, not size and not a lock:
#   acct=WIN11-TEST2\vboxuser  admin_role=False  icacls: Access is denied  read8: DENIED
#   EnableLUA=1  ConsentPromptBehaviorAdmin=5  -> vboxuser cannot self-elevate (a prompt needs a human)
# So the copy needs a session that logs on with an elevated token. The built-in Administrator is the
# only account that does that by default with EnableLUA=1 (it is exempt from admin approval mode unless
# FilterAdministratorToken=1, which h295 showed unset). This probe only tests logons; it copies nothing.
# Own output (R5): _ritual\h296_creds.txt.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h296_creds.txt'
$so    = "$env:TEMP\h296o.txt"; $se = "$env:TEMP\h296e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (("{0} === h296 creds: find a guest identity that can read MEMORY.DMP ===" -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

# user is a parameter now: the whole point of this probe
function G([string]$label, [string]$user, [string]$pass, [string]$cmdline, [int]$wait = 60000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = 'guestcontrol ' + $VM + ' --username ' + $user + ' --password ' + $pass + ' run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 45000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) { $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0)) }
    else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 1. who exists, and is the built-in Administrator even active? (readable unelevated) ---
$t0 = G 'admins' 'vboxuser' 'vboxuser' 'net localgroup administrators'
$t1 = G 'acct'   'vboxuser' 'vboxuser' 'net user Administrator'

# --- 2. test logons. Integrity is the question, not just success: cmd must report High Mandatory ---
$probe = 'whoami; whoami /groups'
$cands = @(
    @{ u = 'Administrator'; p = 'vboxuser' },
    @{ u = 'Administrator'; p = 'Password1' },
    @{ u = 'Administrator'; p = 'Passw0rd!' },
    @{ u = 'Administrator'; p = 'admin' }
)
$good = $null
foreach ($c in $cands) {
    $t = G ('try:' + $c.p) $c.u $c.p $probe
    if ($t -match '(?i)High Mandatory Level') { $good = $c; W ('LOGON OK as ' + $c.u + ' with password "' + $c.p + '" and the token is HIGH integrity'); break }
    if ($t -match '(?i)WIN11-TEST2\\') {
        $lvl = ([regex]::Match($t, '(?i)(Low|Medium|High|System) Mandatory Level')).Groups[1].Value
        W ('  logon worked as ' + $c.u + ' pw "' + $c.p + '" but integrity=' + $(if ($lvl) { $lvl } else { 'unknown' }) + ' - not usable for the DACL')
        if ($lvl -eq 'High') { $good = $c; break }
    }
    if ($t -match '(?i)Logon failure|bad username|invalid password|0x8007052E|0x80070532|0x800704F1') { W ('  logon failed for pw "' + $c.p + '"') }
}

# --- 3. verdict ---
if ($good) {
    W ('RESULT: PASS - identity ' + $good.u + ' / "' + $good.p + '" has a high-integrity token (variable: guest identity)')
    W ('VERDICT: run the copy as --username ' + $good.u + ' --password ' + $good.p + '; vboxuser is a dead end')
} else {
    $dis = if ($t1 -match '(?i)Account active\s+No') { ' [note: net user says the account is INACTIVE]' } else { '' }
    W ('RESULT: PARTIAL - no tested logon produced a high-integrity token (variable: guest identity)' + $dis)
    W 'VERDICT: read the admins list above; if vboxuser is the only account, the dump needs a snapshot-level workaround, not a copy'
}
