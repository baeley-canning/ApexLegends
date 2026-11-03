# upgrade3.ps1 - install boot-resilient launcher (retry + self re-arm) and kick the chain
$base = 'http://10.0.2.2:8080'
$d = 'C:\Users\Public\p37'
$o = @()
$o += 'upgrade3 ' + (Get-Date -f 'HH:mm:ss')
foreach ($f in 'run.cmd', 'once.cmd') {
    try { (New-Object Net.WebClient).DownloadFile("$base/$f", "$d\$f"); $o += ('get ' + $f + ' ok ' + (Get-Item "$d\$f").Length) } catch { $o += ('get ' + $f + ' FAIL ' + $_.Exception.Message) }
}
$o += 'taskkill: ' + ((& taskkill.exe /f /fi "WINDOWTITLE eq *loop.cmd*" 2>&1 | Select-Object -First 3) -join ' | ')
$o += 'kick: ' + ((& schtasks.exe /run /tn p37logon 2>&1) -join ' | ')
$body = $o -join "`r`n"
Set-Content -LiteralPath "$d\upgrade3.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## upgrade3`r`n" + $body)) } catch { }
