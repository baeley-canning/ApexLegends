# t81_st_boot.ps1 - scheduled-task worker: clean chrome boot + CDP first-contact pack.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t81_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== BOOT'

# 1. slaughter ALL our ea-profile browser processes (both engines, clean slate)
foreach ($proc in (Get-CimInstance Win32_Process)) {
    if ($proc.Name -in @('chrome.exe', 'msedge.exe') -and $proc.CommandLine -and
        ($proc.CommandLine -match 'eaprof|remote-debugging-(port=93|port=96)')) {
        J ('KILL ' + $proc.ProcessId + ' ' + $proc.Name)
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 4
Remove-Item "$env:LOCALAPPDATA\eaprof\Singleton*" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\eaprof_edge\Singleton*" -Force -Recurse -ErrorAction SilentlyContinue

# 2. single clean launch (chrome primary) -- QUOTE-BAKED user-data-dir (mandatory working form!)
J 'LAUNCHING CHROME'
Start-Process 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList @(
    '--remote-debugging-port=9333',
    ('--user-data-dir="' + "$env:LOCALAPPDATA" + '\eaprof"'),
    '--remote-allow-origins=*', '--no-first-run', '--no-default-browser-check',
    '--lang=en-US', '--window-size=1300,960', 'https://www.ea.com/login') `
    -RedirectStandardError "$env:TEMP\ea_main_err.txt" -WindowStyle Minimized
J 'CHROME SPAWNED'

# 3. poll port, journal hard
$ok = $false
foreach ($i in 1..30) {
    Start-Sleep -Seconds 2
    $up = $false
    try { $null = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9333/json/version' -TimeoutSec 2).Content; $up = $true } catch {}
    J ("probe $i port=$up")
    if ($up) { $ok = $true; break }
}
if (-not $ok) {
    J 'PORT DEAD - trying EDGE fallback'
    Start-Process 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' -ArgumentList @(
        '--remote-debugging-port=9666',
        ('--user-data-dir=' + "$env:LOCALAPPDATA\eaprof_edge"),
        '--remote-allow-origins=*', '--no-first-run', '--no-default-browser-check',
        '--lang=en-US', '--window-size=1300,960', 'https://www.ea.com/login')
    foreach ($i in 1..25) {
        Start-Sleep -Seconds 2
        try { $null = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9666/json/version' -TimeoutSec 2).Content; $ok = $true; J ('EDGE UP try ' + $i); break } catch { J ("edge probe $i down") }
    }
    if ($ok) { Set-Variable -Name ActivePort -Value 9666 -Scope Global }
} else { Set-Variable -Name ActivePort -Value 9333 -Scope Global }

if (-not $ok) { J 'ALL ENGINES DEAF - GIVING UP'; exit 1 }
J ("ENGINE UP ON PORT " + $ActivePort)

# 4. first-contact pack: targets, DOM read, screenshot
Start-Sleep -Seconds 5
try {
    (Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:" + $ActivePort + "/json/list") -TimeoutSec 8).Content |
        Out-File -Encoding utf8 (Join-Path $here '_cdp_ready2.txt')
    J 'TARGETS SAVED'
} catch { J ('TARGETS FAIL ' + $_.Exception.Message) }

. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port $ActivePort -Match 'ea.com'
if (-not $pg) { $pg = Get-CdpPage -Port $ActivePort -Index 1 }
if ($pg) {
    J ('PAGE ' + $pg.url)
    try {
        $js = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
        $f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
            -Params @{ expression = $js; returnByValue = $true } -Id 5
        if ($f -and $f.result) { $f | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 (Join-Path $here '_dom1_raw.txt'); J 'DOM EVAL DONE' }
    } catch { J ('DOM FAIL ' + $_.Exception.Message) }
    try {
        $s = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
            -Params @{ format = 'jpeg'; quality = 82 } -Id 6
        if ($s -and $s.result -and $s.result.data) {
            [IO.File]::WriteAllBytes((Join-Path $here '_t81_first.jpg'), [Convert]::FromBase64String($s.result.data))
            J 'SCREENSHOT SAVED'
        }
    } catch { J ('SHOT FAIL ' + $_.Exception.Message) }
} else { J 'NO PAGE TARGET FOUND' }
J '=== DONE'
