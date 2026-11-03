$out = Join-Path $env:TEMP 'vmprobe.txt'
$res = @()
foreach ($x in @('127.0.0.1:13389','127.0.0.1:3390','192.168.56.100:3389','192.168.56.101:3389','192.168.56.100:445','192.168.56.101:445','192.168.56.100:135','192.168.56.101:135')) {
    $p = $x.Split(':')
    $c = New-Object System.Net.Sockets.TcpClient
    $ok = $false
    try {
        $iar = $c.BeginConnect($p[0], [int]$p[1], $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500)
        if ($ok) { $c.EndConnect($iar) }
    } catch { $ok = $false }
    $c.Close()
    $res += ('{0} open={1}' -f $x, $ok)
}
Set-Content -LiteralPath $out -Value $res
Get-Content -LiteralPath $out
