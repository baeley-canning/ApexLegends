# h319_svc.ps1 - P0 arm B: put the apexdrv SERVICE ENTRY back (create only, do NOT start).
# Variable: SCM entry visible while the image is NOT resident. No DSE needed to create.
# R4: restore = sc delete apexdrv (or a later h318_reload full arm).
$log = 'C:\Users\Public\p37\h319_svc.out'
function L([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Add-Content -LiteralPath $log -Value $line; Write-Host $line }
Set-Content -LiteralPath $log -Value ('===== h319 svc-entry arm ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
$sys = 'C:\Windows\System32\drivers\apexdrv.sys'
L ('sysfile exists=' + (Test-Path $sys) + ' sha=' + (Get-FileHash $sys -Algorithm SHA256).Hash.Substring(0,12))
$out = & sc.exe create apexdrv type= kernel start= demand binPath= '\SystemRoot\System32\drivers\apexdrv.sys' DisplayName= 'apexdrv' 2>&1
L ('create rc=' + $LASTEXITCODE + ' out=' + (($out -join ' ').Trim()))
Start-Sleep 1
$q = & sc.exe query apexdrv 2>&1
L ('query: ' + (($q -join ' ') -replace '\s+', ' '))
if (($q -join ' ') -match 'STOPPED') { L 'RESULT: PASS - service entry present, STOPPED (image not loaded)'; L 'VERDICT: entry-only arm armed - launch the game now' }
elseif (($q -join ' ') -match 'RUNNING') { L 'RESULT: PARTIAL - entry present and RUNNING (image loaded)' }
else { L ('RESULT: FAIL - ' + (($q -join ' ').Trim())) }
