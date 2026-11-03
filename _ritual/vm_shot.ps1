$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vm_shot.txt'
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
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
Say ("vm_shot {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
Say ("rdp-forward 127.0.0.1:13389 = " + (PortOpen '127.0.0.1' 13389 800))
Say ("vrdp       127.0.0.1:3390  = " + (PortOpen '127.0.0.1' 3390 800))
Say '--- adapters ---'
Get-NetAdapter | ForEach-Object { Say ("  {0} | {1} | {2}" -f $_.Name, $_.Status, $_.MacAddress) }
Say '--- ipv4 ---'
Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object { Say ("  {0} | {1}/{2} | {3}" -f $_.InterfaceAlias, $_.IPAddress, $_.PrefixLength, $_.AddressState) }
Say '--- vm info state ---'
Say ((& $VB showvminfo 'Win11-Test2' --machinereadable 2>&1 | Select-String '^VMState|^GuestMemoryBalloon|^memory|^cpus') -join "`r`n")
Say '--- screenshot ---'
$png = Join-Path $base 'vm_shot.png'
if (Test-Path $png) { Remove-Item $png -Force }
Say ((& $VB controlvm 'Win11-Test2' screenshotpng $png 2>&1) -join "`r`n")
Say ("png exists = " + (Test-Path $png) + "  size=" + (Get-Item $png -EA 0).Length)
Say '--- guest login / autologon state in vbox config ---'
Say ((Select-String -Path 'C:\Users\New User\VirtualBox VMs\Win11-Test2\Win11-Test2.vbox' -Pattern 'AutoLogin|User=' -EA 0 | ForEach-Object { $_.Line.Trim() }) -join "`r`n")
Say '--- end ---'
