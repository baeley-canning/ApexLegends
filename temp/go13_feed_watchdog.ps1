$j='C:\Users\New User\OneDrive\Desktop\cheating\temp\go13_watchdog.txt'
"WAKE $(Get-Date -Format HH:mm:ss)" | Set-Content $j
$feed='C:\Users\New User\OneDrive\Desktop\cheating\temp\qk_feed.json'
while (-not (Test-Path $feed)) { Start-Sleep -Seconds 2 }
Add-Content $j "FEED_SEEN $(Get-Date -Format HH:mm:ss)"
# guard: only launch if no qk_live python currently exists
$have = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -like '*qk_live*' }
if (-not $have) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\New User\OneDrive\Desktop\cheating\temp\go12_consumer.ps1'
    Add-Content $j 'FIRED_GO12'
} else {
    Add-Content $j 'CONSUMER_ALREADY_RUNNING - stand down'
}
Add-Content $j "DONE $(Get-Date -Format HH:mm:ss)"