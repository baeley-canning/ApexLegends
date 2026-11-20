# t77_jpg.ps1 - capture a clean JPEG of the CDP-connected Chrome page (no desktop-crop games).
param(
    [int]$Port = 9333,
    [string]$Match,
    [int]$Index = 1,
    [string]$Tag = 'cdp'
)
. "$PSScriptRoot\_cdp.ps1"
$pg = Get-CdpPage -Port $Port -Index $Index -Match $Match
if (-not $pg) { 'NO_PAGE'; exit 1 }
$frame = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
    -Params @{ format = 'jpeg'; quality = 82 } -Id 9
if (-not $frame -or -not $frame.result -or -not $frame.result.data) { 'SHOT_FAIL'; exit 1 }
$path = Join-Path $PSScriptRoot ("_$Tag.jpg")
[IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($frame.result.data))
'WROTE ' + $path
