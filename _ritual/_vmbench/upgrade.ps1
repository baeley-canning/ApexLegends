# upgrade.ps1 - one-shot: install loop-based cadence (run.cmd/loop.cmd) and start the loop
$base = 'http://10.0.2.2:8080'
$d = 'C:\Users\Public\p37'
$o = @()
$o += 'upgrade ' + (Get-Date -f 'HH:mm:ss')
try { (New-Object Net.WebClient).DownloadFile("$base/run.cmd", "$d\run.cmd"); $o += 'run.cmd ok' } catch { $o += 'run.cmd FAIL ' + $_.Exception.Message }
try { (New-Object Net.WebClient).DownloadFile("$base/loop.cmd", "$d\loop.cmd"); $o += 'loop.cmd ok' } catch { $o += 'loop.cmd FAIL ' + $_.Exception.Message }
Remove-Item -LiteralPath "$d\loop.lock" -ErrorAction SilentlyContinue
Start-Process cmd -ArgumentList '/c', "$d\loop.cmd" -WindowStyle Hidden
$o += 'loop started; files=' + ((Get-ChildItem $d -File | ForEach-Object { $_.Name }) -join ',')
$body = $o -join "`r`n"
Set-Content -LiteralPath "$d\upgrade.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## upgrade`r`n" + $body)) } catch { }
