$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vm_net.txt'
function Say($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
function PortOpen($ip, $port, $ms) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $a = $c.BeginConnect($ip, $port, $null, $null)
        if (-not $a.AsyncWaitHandle.WaitOne($ms)) { $c.Close(); return $false }
        $c.EndConnect($a); $c.Close(); return $true
    } catch { return $false }
}
if (Test-Path $o) { Remove-Item $o -Force }
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
Say ("vm_net {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))

Say '--- host-only adapters ---'
Get-NetIPAddress -AddressFamily IPv4 -EA 0 | Where-Object { $_.InterfaceAlias -like '*Host-Only*' -or $_.InterfaceAlias -like '*VirtualBox*' } |
    ForEach-Object { Say ("  {0}  {1}  {2}" -f $_.InterfaceAlias, $_.IPAddress, $_.PrefixLength) }

Say '--- dhcp lease for guest MAC 08:00:27:45:F5:96 ---'
Say ((& $VB dhcpserver findlease --interface='VirtualBox Host-Only Ethernet Adapter' --mac-address=08:00:27:45:F5:96 2>&1) -join "`r`n")

Say '--- arp on 192.168.56.x ---'
Say (((arp -a) | Select-String '192\.168\.56\.') -join "`r`n")
Say '--- guest net registers (VBox, GA-independent) ---'
Say ((& $VB guestproperty enumerate 'Win11-Test2' 2>&1 | Select-String 'Net|OS/|GuestAdd') -join "`r`n")

$cands = @('192.168.56.101', '192.168.56.102', '192.168.56.103', '192.168.56.10', '192.168.56.11')
Say '--- port sweep on candidates (445 smb / 3389 rdp / 5985 winrm / 135 rpc) ---'
foreach ($ip in $cands) {
    $r = @()
    foreach ($p in 445, 3389, 5985, 135) { $r += ("{0}={1}" -f $p, (PortOpen $ip $p 600)) }
    Say ("  {0}  {1}" -f $ip, ($r -join '  '))
}

$good = $cands | Where-Object { PortOpen $_ 445 600 }
if ($good) {
    $ip = $good[0]
    Say ("--- SMB test against $ip ---")
    Say ((& cmd.exe /c "net use \\$ip\C$ /user:vboxuser password" 2>&1) -join "`r`n")
    Say ((& cmd.exe /c "dir \\$ip\C$" 2>&1 | Select-Object -First 12) -join "`r`n")
    Say '--- WMI/DCOM remote exec test ---'
    try {
        $sec = ConvertTo-SecureString 'password' -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential('vboxuser', $sec)
        $os = Get-CimInstance -ComputerName $ip -Credential $cred -ClassName Win32_OperatingSystem -EA Stop
        Say ("  wmi ok: {0} build {1}" -f $os.Caption, $os.BuildNumber)
        $res = Invoke-CimMethod -ComputerName $ip -Credential $cred -ClassName Win32_Process -MethodName Create `
                -Arguments @{ CommandLine = 'cmd.exe /c echo wmi-exec-ok > C:\Users\vboxuser\wmimark.txt' } -EA Stop
        Say ("  process create: ReturnValue={0} pid={1}" -f $res.ReturnValue, $res.ProcessId)
    } catch { Say ('  wmi ERR: ' + $_.Exception.Message) }
} else { Say '--- no host reached on 445 ---' }
Say '--- end ---'
