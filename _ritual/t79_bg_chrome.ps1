# t79_bg_chrome.ps1 - BACKGROUND worker: bring up CDP-enabled Chrome on port 9333 and prove it end-to-end.
# Runs detached:  Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$here+'\t79_bg_chrome.ps1'
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$poll = Join-Path $here '_t79_poll.txt'
Add-Content -Path $poll -Value ("=== run " + (Get-Date).ToString('HH:mm:ss'))

# 1. kill only OUR cdp-chrome instances (identifiable by their unique profile/port flags)
Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object { $_.CommandLine -match 'eaprof|remote-debugging-port=9333' } |
    ForEach-Object { Add-Content $poll ("KILL " + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
Remove-Item "$env:LOCALAPPDATA\eaprof\Singleton*" -Force -ErrorAction SilentlyContinue

# 2. launch clean
$p = Start-Process 'C:\Program Files\Google\Chrome\Application\chrome.exe' `
    -ArgumentList @('--remote-debugging-port=9333','--user-data-dir',"$env:LOCALAPPDATA\eaprof",
        '--remote-allow-origins=*','--no-first-run','--no-default-browser-check',
        '--lang=en-US','--window-size=1300,960','https://www.ea.com/login') -PassThru
Add-Content $poll ("LAUNCHED PID " + $p.Id)

# 3. patient poll, every round journaled (survives on its own clock, nobody kills us here)
$ok = $false
foreach ($i in 1..70) {
    Start-Sleep -Seconds 2
    $alive = -not $p.HasExited
    $up = $false
    try { $null = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9333/json/version' -TimeoutSec 2).Content; $up = $true } catch {}
    Add-Content $poll ("try $i alive=$alive port=$up")
    if ($up -and $alive) { $ok = $true; break }
    if (-not $alive) { Add-Content $poll ("EXITCODE " + $p.ExitCode); break }
}

if (-not $ok) { Add-Content $poll 'RESULT FAILED'; exit 1 }

# 4. capture proof: target list + immediate CDP screenshot of the login page
Add-Content $poll 'RESULT PORT_UP'
(Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9333/json/list' -TimeoutSec 8).Content |
    Out-File -Encoding utf8 (Join-Path $here '_cdp_ready.txt')
Start-Sleep -Seconds 6
. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { $pg = Get-CdpPage -Port 9333 -Index 1 }
if ($pg) {
    $f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 82 } -Id 3
    if ($f -and $f.result -and $f.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t79_first.jpg'), [Convert]::FromBase64String($f.result.data))
        Add-Content $poll 'SCREENSHOT SAVED'
    }
} else { Add-Content $poll 'NO PAGE TARGET' }
