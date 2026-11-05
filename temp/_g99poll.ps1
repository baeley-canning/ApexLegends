# _g99poll.ps1 -- detached watcher for the p99 guest log. Sleep-based waits in the chat
# turn get reaped, so the waiting happens in its own process and the chat only reads the file.
$src = 'C:\p37vm\guest-p99.log'
$o = 'c:\Users\New User\OneDrive\Desktop\cheating\temp\_g99ad.txt'
$seen = 0
$deadline = (Get-Date).AddSeconds(420)
while ((Get-Date) -lt $deadline) {
    $lines = @()
    if (Test-Path -LiteralPath $src) { $lines = [IO.File]::ReadAllLines($src) }
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'p99 guest-entry') { $idx = $i } }
    if ($idx -ge 0) {
        $body = $lines[($idx + 1)..($lines.Count - 1)] | Where-Object { $_ -notmatch 'POST /log' }
        $body | Out-File -LiteralPath $o -Encoding utf8
        if ($body -match 'P99_DONE|NO_DEVICE|READ_FAITHFUL|READ_UNSTABLE|READ_FIXED_STUB') { break }
    } else {
        ('waiting ' + (Get-Date -f 'HH:mm:ss') + ' src=' + (Test-Path -LiteralPath $src) + ' n=' + $lines.Count) | Out-File -LiteralPath $o -Encoding utf8
    }
    Start-Sleep -Seconds 6
}
