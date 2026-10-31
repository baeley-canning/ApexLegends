# ============================================================================
# build\diag_driver_imagepath.ps1 — ELEVATED: prove the leading-space theory.
#   sc.exe create ... "binPath= X" stores ' X' (leading space) for kernel
#   drivers; NtLoadDriver then fails with STATUS_OBJECT_NAME_INVALID (123).
#   Writing ImagePath straight into the registry removes the space.
# ============================================================================
$ErrorActionPreference = 'Continue'
$root  = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev    = Join-Path $root 'build\phase1_evidence'
$log   = Join-Path $ev 'driver_imagepath_diag.txt'
$canon = 'C:\Windows\System32\drivers\apexdrv.sys'
$key   = 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'

"== ImagePath diagnostic $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"image : $canon ($((Get-Item $canon).Length) bytes) sig=$((Get-AuthenticodeSignature $canon).Status)" |
    Out-File -Encoding utf8 -Append $log

sc.exe delete apexdrv *> $null
Start-Sleep -Milliseconds 400

(sc.exe create apexdrv type= kernel start= demand ('binPath= ' + $canon)) 2>&1 |
    Out-File -Encoding utf8 -Append $log
"after sc create : '$((Get-ItemProperty $key).ImagePath)'" | Out-File -Encoding utf8 -Append $log

Set-ItemProperty -Path $key -Name ImagePath -Value ('\??\' + $canon) -Type ExpandString
"after reg write : '$((Get-ItemProperty $key).ImagePath)'" | Out-File -Encoding utf8 -Append $log

$start = (sc.exe start apexdrv) 2>&1
"start           : $(($start -join ' ').Trim())" | Out-File -Encoding utf8 -Append $log
(sc.exe query apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
"service state   : $((Get-Service apexdrv).Status)" | Out-File -Encoding utf8 -Append $log
"device present  : $([bool](Get-ChildItem '\\.\Global\ApexDrv' -ErrorAction SilentlyContinue))" |
    Out-File -Encoding utf8 -Append $log

# leftovers must not block the next step
sc.exe stop apexdrv *> $null
(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddMinutes(-3) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Service Control Manager' } | Select-Object -First 4 |
    ForEach-Object { "[$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.Id): $($_.Message -replace '\s+', ' ')" }) |
    Out-File -Encoding utf8 -Append $log

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'imagepath_done.txt')
