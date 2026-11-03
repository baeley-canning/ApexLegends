param(
  [Parameter(Mandatory=$true)][ValidateSet('eval','nav','shot','targets','newtab','click','type')][string]$Action,
  [string]$Expr = '',
  [string]$Url  = '',
  [string]$Out  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_cdp.txt',
  [int]$Port = 9222
)
$ErrorActionPreference = 'Stop'
[void][Net.WebSockets.ClientWebSocket]

function Send-Cmd($ws, [int]$id, [string]$method, $params) {
  $msg = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 12 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
  $ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
  $buf = New-Object byte[] 524288
  $sb  = New-Object Text.StringBuilder
  while ($true) {
    $seg = [ArraySegment[byte]]::new($buf)
    $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None).Result
    [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
    if ($r.EndOfMessage) { break }
  }
  return ($sb.ToString() | ConvertFrom-Json)
}

$base = "http://127.0.0.1:$Port"
$all = Invoke-RestMethod -Uri "$base/json/list" -TimeoutSec 15
$tab = $null
foreach ($t in $all) { if ($t.type -eq 'page' -and $t.url -match '^https?://') { $tab = $t; break } }

function Open-Tab {
  $ws = [Net.WebSockets.ClientWebSocket]::new()
  $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  return $ws
}

switch ($Action) {
  'targets' {
    ($all | ForEach-Object { $_.type + ' | ' + $_.title + ' | ' + $_.url }) -join "`n" | Set-Content -LiteralPath $Out -Encoding utf8
    exit 0
  }
  'newtab' {
    $p = Invoke-RestMethod -Uri "$base/json/new?$Url" -Method Put -TimeoutSec 20
    ($p.id + ' | ' + $Url) | Set-Content -LiteralPath $Out -Encoding utf8
    exit 0
  }
  'nav' {
    $ws = Open-Tab
    [void](Send-Cmd $ws 1 'Page.navigate' @{ url = $Url })
    Start-Sleep 3
    $ws.Dispose()
    ('nav ' + $Url) | Set-Content -LiteralPath $Out -Encoding utf8
    exit 0
  }
  'shot' {
    $ws = Open-Tab
    $r = Send-Cmd $ws 1 'Page.captureScreenshot' @{ format = 'png' }
    [IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($r.result.data))
    $ws.Dispose()
    ('shot ' + $Out) | Set-Content -LiteralPath 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_cdp.txt' -Encoding utf8
    exit 0
  }
  'type' {
    $ws = Open-Tab
    [void](Send-Cmd $ws 1 'Runtime.evaluate' @{ expression = "(function(){var e=document.querySelector('" + $Expr + "');if(!e)return 0;e.focus();e.select&&e.select();return 1;})()"; returnByValue = $true })
    [void](Send-Cmd $ws 2 'Input.insertText' @{ text = $Url })
    $ws.Dispose()
    ('typed ' + $Expr) | Set-Content -LiteralPath $Out -Encoding utf8
    exit 0
  }
  'click' {
    $ws = Open-Tab
    $js = "(function(){var e=document.querySelector('" + $Expr + "');if(!e)return 'miss';e.scrollIntoView({block:'center'});var r=e.getBoundingClientRect();return Math.round(r.x+r.width/2)+','+Math.round(r.y+r.height/2);})()"
    $pos = Send-Cmd $ws 1 'Runtime.evaluate' @{ expression = $js; returnByValue = $true }
    $xy = $pos.result.result.value
    if ($xy -eq 'miss') { 'miss ' + $Expr | Set-Content -LiteralPath $Out -Encoding utf8; $ws.Dispose(); exit 1 }
    $parts = $xy.Split(',')
    $bx = [int]$parts[0]; $by = [int]$parts[1]
    foreach ($t in @('mouseMoved', 'mousePressed', 'mouseReleased')) {
      [void](Send-Cmd $ws 2 'Input.dispatchMouseEvent' @{ type = $t; x = $bx; y = $by; button = 'left'; clickCount = 1; buttons = $(if ($t -eq 'mouseReleased') { 0 } else { 1 }) })
    }
    $ws.Dispose()
    ('click ' + $Expr + ' @' + $xy) | Set-Content -LiteralPath $Out -Encoding utf8
    exit 0
  }
  'eval' {
    $ws = Open-Tab
    if ($Expr.StartsWith('@')) { $Expr = (Get-Content -LiteralPath $Expr.Substring(1) -Raw) }
    $r = Send-Cmd $ws 1 'Runtime.evaluate' @{ expression = $Expr; returnByValue = $true; awaitPromise = $true }
    $ws.Dispose()
    if ($r.result.exceptionDetails) {
      ('EX ' + $r.result.exceptionDetails.exception.description) | Set-Content -LiteralPath $Out -Encoding utf8
    } elseif ($r.result.result.value -is [string]) {
      $r.result.result.value | Set-Content -LiteralPath $Out -Encoding utf8
    } else {
      ($r.result.result.value | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Out -Encoding utf8
    }
    exit 0
  }
}
