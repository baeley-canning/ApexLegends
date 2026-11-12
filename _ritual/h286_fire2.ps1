# h286_fire2.ps1 - plan B fire (v2). Remote `schtasks /s 192.168.56.101` is dead right now
# (pw=password -> "ERROR: The request is not supported.", pw=vboxuser -> 30 s hang; see
# h286_fire.txt), so the tick is triggered from INSIDE the guest via guestcontrol. Credential
# vboxuser/vboxuser is durable per STATE 06/11 10:45 (works locked, medium IL). The trigger
# only STARTS the SYSTEM task; the harness still runs as SYSTEM.
# v2 fix: the helper was named GC - an alias of Get-Content, and ALIASES OUTRANK FUNCTIONS in
# PowerShell, so v1's probe/fire calls ran Get-Content instead of VBoxManage and the output file
# was garbage. Helper renamed Gcx. Channel probe (whoami) first, 45 s cap per call (R5).
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_fire2.txt'
$so  = "$env:TEMP\h286_gco.txt"; $se = "$env:TEMP\h286_gce.txt"
Remove-Item -LiteralPath $out -Force -EA 0
Remove-Item -LiteralPath $so -Force -EA 0
Remove-Item -LiteralPath $se -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function Gcx([string]$label, [string[]]$argv) {
    $p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    if ($p.WaitForExit(45000)) {
        $t = (((Get-Content $so -Raw -EA 0) + (Get-Content $se -Raw -EA 0)) -replace '\s+', ' ').Trim()
        W ($label + ' rc=' + $p.ExitCode + ' out=[' + $t + ']')
        return $p.ExitCode
    }
    try { $p.Kill() } catch { }
    W ($label + ' TIMEOUT 45 s (killed)')
    return 1
}
W '=== h286 fire2 v2: gc probe + p37tick trigger from inside ==='
$probe = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','20000','--','cmd.exe','/c','whoami')
if ((Gcx 'probe[whoami]' $probe) -ne 0) {
    W 'RESULT: FIRE2 FAILED - gc channel itself dead; next: controlvm reset'
    W 'VERDICT: tick not fired'
    exit 1
}
$fire = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run','--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','30000','--','cmd.exe','/c','schtasks /run /tn p37tick')
if ((Gcx 'fire[schtasks-run]' $fire) -eq 0) { W 'RESULT: FIRED via gc (p37tick started; harness runs as SYSTEM)' }
else { W 'RESULT: FIRE2 FAILED - gc alive but task trigger refused; next: controlvm reset' }
W 'VERDICT: poll C:\p37vm\guest-h286.log'

