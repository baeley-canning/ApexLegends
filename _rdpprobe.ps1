$ips = @('10.0.2.15','10.0.2.2','192.168.56.2','192.168.4.177')
foreach ($ip in $ips) {
    try {
        $tcp = New-Object System.Net.Sockets.TCPClient
        $task = $tcp.ConnectAsync($ip, 3389)
        if ($task.Wait([timespan]::FromMilliseconds(5000))) { Write-Output "$ip:3389 OPEN" } else { Write-Output "$ip:3389 closed/timeout" }
    } catch {
        Write-Output "$ip:3389 error $($_.Exception.Message)"
    }
}
