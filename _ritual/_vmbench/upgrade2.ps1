# upgrade2.ps1 - install fire-and-forget cadence (run.cmd + once.cmd), kill stray loops
$base = 'http://10.0.2.2:8080'
$d = 'C:\Users\Public\p37'
$o = @()
$o += 'upgrade2 ' + (Get-Date -f 'HH:mm:ss')
foreach ($f in 'run.cmd', 'once.cmd') {
    try { (New-Object Net.WebClient).DownloadFile("$base/$f", "$d\$f"); $o += ('get ' + $f + ' ok ' + (Get-Item "$d\$f").Length) } catch { $o += ('get ' + $f + ' FAIL ' + $_.Exception.Message) }
}
$o += 'taskkill: ' + ((& taskkill.exe /f /fi "WINDOWTITLE eq *loop.cmd*" 2>&1 | Select-Object -First 4) -join ' | ')
Remove-Item -LiteralPath "$d\loop.lock" -ErrorAction SilentlyContinue
$o += 'files=' + ((Get-ChildItem $d -File | ForEach-Object { $_.Name }) -join ',')
$body = $o -join "`r`n"
Set-Content -LiteralPath "$d\upgrade2.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## upgrade2`r`n" + $body)) } catch { }
