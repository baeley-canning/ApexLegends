# minimal HTTP server for guest->host payload transfer (no URL ACL needed)
$root = 'C:\p37vm\payload'
$log = 'C:\p37vm\server.log'
$guestlog = 'C:\p37vm\guest.log'
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, 8080)
$listener.Start()
Add-Content -LiteralPath $log -Value ('listening ' + (Get-Date -f 'HH:mm:ss'))
while ($true) {
    $c = $listener.AcceptTcpClient()
    try {
        $ns = $c.GetStream()
        $hdrBytes = New-Object System.Collections.Generic.List[byte]
        $prev = 0
        while ($true) {
            $b = $ns.ReadByte()
            if ($b -lt 0) { break }
            $hdrBytes.Add([byte]$b)
            $n = $hdrBytes.Count
            if ($n -ge 4 -and $hdrBytes[$n-4] -eq 13 -and $hdrBytes[$n-3] -eq 10 -and $hdrBytes[$n-2] -eq 13 -and $hdrBytes[$n-1] -eq 10) { break }
            if ($n -gt 16384) { break }
        }
        if ($hdrBytes.Count -eq 0) { $c.Close(); continue }
        $hdrText = [Text.Encoding]::ASCII.GetString($hdrBytes.ToArray())
        $lines = $hdrText -split "`r`n"
        $line = $lines[0]
        if ([string]::IsNullOrWhiteSpace($line)) { $c.Close(); continue }
        $parts = $line.Split(' ')
        $method = $parts[0]
        $path = $parts[1]
        $vm = 'main'
        if ($path -match '\?vm=([A-Za-z0-9_-]+)') { $vm = $matches[1]; $path = $path.Split('?')[0] }
        $len = 0; $expect = $false
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $h = $lines[$i]
            if ($h -match '^(?i)Content-Length:\s*(\d+)') { $len = [int]$matches[1] }
            if ($h -match '^(?i)Expect:\s*100-continue') { $expect = $true }
        }
        if ($method -eq 'POST') {
            if ($expect) {
                $cont = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n")
                $ns.Write($cont, 0, $cont.Length); $ns.Flush()
            }
            $buf = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) { $n = $ns.Read($buf, $read, $len - $read); if ($n -le 0) { break }; $read += $n }
            $body = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
            $guestlog = "C:\p37vm\guest-$vm.log"
            Add-Content -LiteralPath $guestlog -Value ("===== POST " + $path + " " + (Get-Date -f 'HH:mm:ss'))
            Add-Content -LiteralPath $guestlog -Value $body
            $resp = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK")
            $ns.Write($resp, 0, $resp.Length)
            Add-Content -LiteralPath $log -Value ('POST ' + $path + ' bytes=' + $read)
        } else {
            $name = [IO.Path]::GetFileName($path)
            $file = Join-Path $root $name
            if (Test-Path -LiteralPath $file) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $hdr = [Text.Encoding]::ASCII.GetBytes(("HTTP/1.1 200 OK`r`nContent-Length: " + $bytes.Length + "`r`nConnection: close`r`n`r`n"))
                $ns.Write($hdr, 0, $hdr.Length)
                $ns.Write($bytes, 0, $bytes.Length)
                Add-Content -LiteralPath $log -Value ('GET ' + $name + ' ok ' + $bytes.Length)
            } else {
                $nf = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                $ns.Write($nf, 0, $nf.Length)
                Add-Content -LiteralPath $log -Value ('GET ' + $name + ' 404')
            }
        }
        $ns.Flush()
    } catch {
        Add-Content -LiteralPath $log -Value ('err ' + $_.Exception.Message)
    } finally {
        try { $c.Client.Shutdown([Net.Sockets.SocketShutdown]::Send); Start-Sleep -Milliseconds 120 } catch { }
        $c.Close()
    }
}
