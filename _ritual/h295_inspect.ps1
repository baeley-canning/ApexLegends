# h295_inspect.ps1 - probe #295 (variable: guest identity/ACL/UAC facts that decide HOW MEMORY.DMP can be read).
# h294 proved the size path is fine (guest 391,099,508 b, host 0) and failed only at the ACL:
#   "Guest file could not be opened: Access to guest file \"C:\\Windows\\MEMORY.DMP\" denied"
# That is a medium-integrity token hitting an Administrators/SYSTEM-only DACL. Three routes exist and
# they fail differently, so pick with facts, not guesses:
#   (a) token is already full            -> copyfrom works as-is
#   (b) admin + ConsentPromptBehaviorAdmin=0 -> Start-Process -Verb RunAs is seamless (no prompt)
#   (c) admin + prompting UAC, or not admin  -> schtasks /ru SYSTEM (needs admin to create) or FAIL
# Read-only: this probe mutates nothing on the guest. Own output (R5): _ritual\h295_inspect.txt.
$ErrorActionPreference = 'Continue'
$vb    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM    = 'Win11-Test2'
$d     = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out   = Join-Path $d 'h295_inspect.txt'
$so    = "$env:TEMP\h295o.txt"; $se = "$env:TEMP\h295e.txt"
Set-Content -LiteralPath $out -Encoding ascii -Value (("{0} === h295 inspect: can the session read MEMORY.DMP, and which elevation route works ===" -f (Get-Date -f 'HH:mm:ss.fff')))
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) -Encoding ascii }

function G([string]$label, [string]$cmdline, [int]$wait = 120000) {
    Remove-Item -LiteralPath $so, $se -Force -EA 0
    $line = 'guestcontrol ' + $VM + ' --username vboxuser --password vboxuser run --exe "C:\Windows\System32\cmd.exe" --wait-stdout --wait-stderr --timeout 120000 -- cmd.exe /c ' + $cmdline
    $p = Start-Process -FilePath $vb -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $t = ''
    if ($p.WaitForExit($wait)) {
        $t = ((Get-Content -LiteralPath $so -Raw -EA 0) + (Get-Content -LiteralPath $se -Raw -EA 0))
        W ($label + ' rc=' + $p.ExitCode)
    } else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT (killed)') }
    foreach ($ln in ($t -split "`r?`n")) { if ($ln.Trim()) { W ('  ' + $label + ' | ' + $ln.Trim()) } }
    return $t
}

# --- 0. host side: is there already a shared folder that avoids the copy entirely? ---
$sf = (& $vb showvminfo $VM --machinereadable 2>&1) -join "`n"
foreach ($ln in ($sf -split "`r?`n")) { if ($ln -match '(?i)sharedfolder|^VMState') { W ('  vm  | ' + $ln.Trim()) } }

# --- 1. who is the session, and is the token filtered? (one call: identity + admin role + group marks) ---
$c1 = 'powershell -NoProfile -Command "$id=[Security.Principal.WindowsIdentity]::GetCurrent(); ''acct=''+$id.Name; ''admin_role=''+([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); foreach($g in $id.Groups){ try{ $n=$g.Translate([Security.Principal.NTAccount]).Value }catch{ $n=$g.Value }; if($n -match ''Administrators|High Mandatory|Medium Mandatory|Mandatory Label''){ ''grp=''+$n } }"'
$t1 = G 'whoami' $c1

# --- 2. the DACL itself: proves the deny is ACL and not a lock ---
$c2 = 'icacls C:\Windows\MEMORY.DMP'
$t2 = G 'icacls' $c2

# --- 3. UAC shape on the guest: decides whether -Verb RunAs prompts (route b) or must be avoided ---
$c3 = 'powershell -NoProfile -Command "$k=''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System''; foreach($n in ''EnableLUA'',''ConsentPromptBehaviorAdmin'',''FilterAdministratorToken'',''LocalAccountTokenFilterPolicy''){ $v=(Get-ItemProperty -Path $k -Name $n -EA 0).$n; ''uac ''+$n+''=''+$v }"'
$t3 = G 'uac' $c3

# --- 4. can the session actually read one byte? direct evidence beats inference from the DACL ---
$c4 = 'powershell -NoProfile -Command "try{ $fs=[IO.File]::Open(''C:\Windows\MEMORY.DMP'',''Open'',''Read'',''ReadWrite''); ''read_open=OK len=''+$fs.Length; $b=New-Object byte[] 8; [void]$fs.Read($b,0,8); ''hdr=''+([BitConverter]::ToString($b)); $fs.Dispose() }catch{ ''read_open=DENIED ''+$_.Exception.GetType().Name }"'
$t4 = G 'read8' $c4

# --- verdict: name the route, do not perform it here ---
$isAdmin = ($t1 -match 'admin_role=True')
$noPrompt = ($t3 -match 'ConsentPromptBehaviorAdmin=0')
$canRead = ($t4 -match 'read_open=OK')
if ($canRead) { W 'ROUTE: (a) direct - copyfrom will work as-is' }
elseif ($isAdmin -and $noPrompt) { W 'ROUTE: (b) elevated - Start-Process -Verb RunAs will not prompt' }
elseif ($isAdmin) { W 'ROUTE: (c) admin but UAC prompts - prefer schtasks /ru SYSTEM (needs the same admin rights to create)' }
else { W 'ROUTE: none - the session is not an administrator; the DACL cannot be crossed from here' }
$ev = if ($canRead) { 'CAN' } elseif ($isAdmin) { 'CAN(ELEV)' } else { 'CANNOT' }
W ('RESULT: PASS - identity/ACL read back (variable: guest identity); session ' + $ev + ' reach MEMORY.DMP; admin=' + $isAdmin + ' uac_no_prompt=' + $noPrompt)
W 'VERDICT: follow the ROUTE line; the dump bytes are still the only evidence source, nothing was copied yet'
