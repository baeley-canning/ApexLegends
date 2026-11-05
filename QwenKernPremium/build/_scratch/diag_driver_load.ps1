# ============================================================================
# build\diag_driver_load.ps1  — ELEVATED: why does StartService return 123?
# Loads the SAME signed image from the canonical driver directory, prints the
# SCM's own message, and dumps the System + CodeIntegrity events that the
# failed StartService produced.
# ============================================================================
$ErrorActionPreference = 'Continue'
$root   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev     = Join-Path $root 'build\phase1_evidence'
$log    = Join-Path $ev 'driver_load_diag.txt'
$staged = 'C:\ProgramData\QwenKern\apexdrv.sys'
$canon  = 'C:\Windows\System32\drivers\apexdrv.sys'

"== driver load diagnostic $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"source : $staged" | Out-File -Encoding utf8 -Append $log

Copy-Item $staged $canon -Force
$sig = Get-AuthenticodeSignature $canon
"target : $canon ($((Get-Item $canon).Length) bytes) signature=$($sig.Status)" |
    Out-File -Encoding utf8 -Append $log

if (Get-Service apexdrv -ErrorAction SilentlyContinue) {
    Stop-Service apexdrv -Force -ErrorAction SilentlyContinue
    (sc.exe delete apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
    Start-Sleep -Milliseconds 500
}

(sc.exe create apexdrv type= kernel start= demand ('binPath= ' + '\??\' + $canon)) 2>&1 |
    Out-File -Encoding utf8 -Append $log
(sc.exe qc apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log

$startOutput = (sc.exe start apexdrv) 2>&1
$startOutput | Out-File -Encoding utf8 -Append $log
"net start apexdrv:" | Out-File -Encoding utf8 -Append $log
(net start apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
(sc.exe query apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log

# --- what the kernel said ---------------------------------------------------
"--- System log (SCM / CodeIntegrity, last 10 min) ---" | Out-File -Encoding utf8 -Append $log
Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Service Control Manager|CodeIntegrity|Kernel-Boot|Kernel-PnP' } |
    Select-Object -First 12 |
    ForEach-Object { "[$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.ProviderName) $($_.Id): $($_.Message -replace '\s+', ' ')" } |
    Out-File -Encoding utf8 -Append $log

"--- CodeIntegrity/Operational ---" | Out-File -Encoding utf8 -Append $log
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 8 -ErrorAction SilentlyContinue |
    ForEach-Object { "[$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.Id): $($_.Message -replace '\s+', ' ')" } |
    Out-File -Encoding utf8 -Append $log

"--- device guard / testsigning state ---" | Out-File -Encoding utf8 -Append $log
(Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue |
    Select-Object SecurityServicesRunning, VirtualizationBasedSecurityStatus | Format-List | Out-String) |
    Out-File -Encoding utf8 -Append $log
(bcdedit /enum '{current}' | Select-String -Pattern 'testsigning|nointegritychecks|hypervisorlaunchtype') 2>&1 |
    Out-File -Encoding utf8 -Append $log

(sc.exe stop apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
(sc.exe delete apexdrv) 2>&1 | Out-File -Encoding utf8 -Append $log
'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'diag_done.txt')
