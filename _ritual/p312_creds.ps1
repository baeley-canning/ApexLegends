# p312_creds.ps1 - probe #312 (variable: credential/domain matrix for the session logon)
# The session now opens but the logon is refused for vboxuser/vboxuser. A GA-installed account often
# carries a blank or different password, and a wrong --domain fails the same way. Try the variants
# once each with a short timeout; nothing else changes.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p312.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
$variants = @(
    @{ n = 'u_pw';    a = @('--username', 'vboxuser', '--password', 'vboxuser') },
    @{ n = 'u_blank'; a = @('--username', 'vboxuser', '--password', '') },
    @{ n = 'u_wg';    a = @('--username', 'vboxuser', '--password', 'vboxuser', '--domain', 'WORKGROUP') },
    @{ n = 'admin_pw'; a = @('--username', 'Administrator', '--password', 'vboxuser') }
)
foreach ($x in $variants) {
    $a = $x.a + @('--timeout', '45000', '--wait-stdout', '--wait-stderr', '--exe', 'C:\Windows\System32\cmd.exe', '--', 'cmd', '/c echo OK')
    $o = & $v guestcontrol $VM run @a 2>&1
    $line = ($o -join ' ')
    if ($line.Length -gt 200) { $line = $line.Substring(0, 200) }
    Say ('{0} rc={1} o={2}' -f $x.n, $LASTEXITCODE, $line)
    if ($LASTEXITCODE -eq 0) { Say ('WORKING=' + $x.n) }
}
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', ''))
Say 'END'