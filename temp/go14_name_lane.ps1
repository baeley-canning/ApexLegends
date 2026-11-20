$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$t=Join-Path $repo 'temp'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
# ── kill any incumbent producer first (single-variable hygiene: one producer at a time) ──
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue |
    Where-Object { $_.CommandLine -like '*qk_va*--emit*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Milliseconds 500
$eo=Join-Path $t 'emit_out6.txt'; $ee=Join-Path $t 'emit_err6.txt'
Remove-Item $eo,$ee -EA SilentlyContinue
Start-Process -FilePath $py -WorkingDirectory $repo -WindowStyle Hidden `
    -RedirectStandardOutput $eo -RedirectStandardError $ee `
    -ArgumentList @('-u',('"'+(Join-Path $repo 'ext\qk_va.py')+'"'),'--emit','--hz=10','--secs=300')
$lc=Join-Path $repo 'temp\go12_consumer.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $lc
$j=Join-Path $t 'go14_name_lane.txt'
"WAKE $(Get-Date -Format HH:mm:ss)" | Set-Content $j
Add-Content $j 'NOTE=name-lane fallback (NO --peb-first); killed incumbent producer if any'
Add-Content $j 'VERDICT: NAME_LANE_FIRED'