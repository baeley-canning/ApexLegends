# _cdp.ps1 - minimal zero-dependency Chrome DevTools Protocol bridge for PS 5.1.
# Dot-source me:  . "$PSScriptRoot\_cdp.ps1"
Set-StrictMode -Version 2

function Get-HttpJson {
    param([Parameter(Mandatory)][string]$Url)
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 15
    return ,($resp.Content | ConvertFrom-Json)
}

function Read-CdpMessage {
    param([System.Net.WebSockets.ClientWebSocket]$Ws)
    $chunk = New-Object byte[] 2097152
    $ms = New-Object System.IO.MemoryStream
    while ($true) {
        $seg = [ArraySegment[byte]]::new($chunk)
        $res = $Ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None).Result
        if ($res.Count -gt 0) { [void]$ms.Write($chunk, 0, $res.Count) }
        if ($res.EndOfMessage) { break }
    }
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Invoke-CdpCmd {
    param(
        [Parameter(Mandatory)][string]$WsUrl,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params,
        [int]$Id = 1,
        [int]$TimeoutMs = 45000
    )
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        $ct = [System.Threading.CancellationToken]::None
        $ws.ConnectAsync([Uri]$WsUrl, $ct).Wait()
        $body = @{ id = $Id; method = $Method }
        if ($Params) { $body.params = $Params }
        $json = $body | ConvertTo-Json -Depth 8 -Compress
        $payload = [System.Text.Encoding]::UTF8.GetBytes($json)
        $ws.SendAsync([ArraySegment[byte]]::new($payload),
            [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
            if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { break }
            $txt = Read-CdpMessage $ws
            try { $frame = $txt | ConvertFrom-Json } catch { continue }
            if ($frame.PSObject.Properties['id'] -and $frame.id -eq $Id) { return $frame }
        }
        return $null
    } finally {
        try { $ws.Dispose() } catch {}
    }
}

function Get-CdpPage {
    param([int]$Port = 9333, [int]$Index = 1, [string]$Match)
    $targets = Get-HttpJson "http://127.0.0.1:$Port/json/list"
    $pages = @($targets | Where-Object { $_.type -eq 'page' })
    if ($Match) {
        foreach ($p in $pages) {
            if (($p.url -match $Match) -or ($p.title -match $Match)) { return $p }
        }
        return $null
    }
    if ($pages.Count -ge $Index) { return $pages[$Index - 1] }
    return $null
}
