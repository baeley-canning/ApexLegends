# t82_st_ab.ps1 - A/B: windowed (9333) vs headless (9401) chrome, stderr captured, port truth journaled.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t82_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== AB BOOT'

Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'chrome.exe' -and $_.CommandLine -and $_.CommandLine -match 'eaprof' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3

$errA = "$env:TEMP\ea_errA.txt"
$errB = "$env:TEMP\ea_errB.txt"
Remove-Item $errA, $errB -Force -ErrorAction SilentlyContinue

# A: windowed, equals-joined quoted dir
$pA = Start-Process 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList @(
        '--remote-debugging-port=9333',
        ('--user-data-dir="' + "$env:LOCALAPPDATA" + '\eaprof"'),
        '--remote-allow-origins=*', '--no-first-run', 'https://www.example.com') `
    -RedirectStandardError $errA -RedirectStandardOutput "$env:TEMP\ea_outA.txt" -WindowStyle Minimized -PassThru
J ('A(windows) pid ' + $pA.Id)

# B: headless
$pB = Start-Process 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList @(
        '--remote-debugging-port=9401', '--headless=new',
        ('--user-data-dir="' + "$env:LOCALAPPDATA" + '\eaprofhl"'),
        '--remote-allow-origins=*', '--no-first-run', 'https://www.example.com') `
    -RedirectStandardError $errB -RedirectStandardOutput "$env:TEMP\ea_outB.txt" -PassThru
J ('B(headless) pid ' + $pB.Id)

$okA = $false; $okB = $false
foreach ($i in 1..10) {
    Start-Sleep -Seconds 2
    if (-not $okA) { try { $null = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9333/json/version' -TimeoutSec 2).Content; $okA = $true; J ('A UP try ' + $i) } catch {} }
    if (-not $okB) { try { $null = (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9401/json/version' -TimeoutSec 2).Content; $okB = $true; J ('B UP try ' + $i) } catch {} }
    if ($okA -and $okB) { break }
}
J ('VERDICT A=' + $okA + ' B=' + $okB)
J '--- errA:';   Get-Content $errA -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object { J ('A| ' + $_) }
J '--- errB:';   Get-Content $errB -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object { J ('B| ' + $_) }
J '=== DONE'
