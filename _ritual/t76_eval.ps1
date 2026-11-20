# t76_eval.ps1 - run JS in a CDP-connected Chrome tab, save JSON result to artifact.
param(
    [int]$Port = 9333,
    [string]$Match,
    [int]$Index = 1,
    [string]$Expr,
    [string]$JsPath,
    [string]$Out
)
. "$PSScriptRoot\_cdp.ps1"
if ($JsPath) { $Expr = [IO.File]::ReadAllText($JsPath) }
if (-not $Expr) { if ($Out) { 'NO_EXPR' | Out-File -Encoding utf8 $Out }; 'NO_EXPR'; exit 1 }
$pg = Get-CdpPage -Port $Port -Index $Index -Match $Match
if (-not $pg) { if ($Out) { 'NO_PAGE' | Out-File -Encoding utf8 $Out }; 'NO_PAGE'; exit 1 }
$frame = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $Expr; returnByValue = $true; awaitPromise = $true } -Id 7
$value = $null; $err = $null
if ($frame -and $frame.result) {
    if ($frame.result.result) { $value = $frame.result.result.value }
    if ($frame.result.exceptionDetails) { $err = $frame.result.exceptionDetails.text }
}
$report = @{ value = $value; error = $err; url = $pg.url; title = $pg.title } | ConvertTo-Json -Depth 6 -Compress
if ($Out) { $report | Out-File -Encoding utf8 $Out }
$report
