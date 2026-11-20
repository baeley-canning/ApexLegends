$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$t=Join-Path $repo 'temp'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$lf=Join-Path $t 'live_out5.txt'
$le=Join-Path $t 'live_err5.txt'
Remove-Item $lf,$le -EA SilentlyContinue
Start-Process -FilePath $py -WorkingDirectory $repo -WindowStyle Hidden `
    -RedirectStandardOutput $lf -RedirectStandardError $le `
    -ArgumentList @('-u',('"'+(Join-Path $repo 'ext\qk_live.py')+'"'),'--from-feed','--seconds=330')
$j=Join-Path $t 'go12_consumer.txt'
"WAKE $(Get-Date -Format HH:mm:ss)" | Set-Content $j
Add-Content $j 'PREV_PAIR=live_out4 (EXPIRED 23:14:35, PARTIAL R9)'
Add-Content $j 'VERDICT: CONSUMER_REARMED'