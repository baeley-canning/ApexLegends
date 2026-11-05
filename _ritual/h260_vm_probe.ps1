# h260_vm_probe.ps1 - GUEST side of the h260 bench. Loads the v3 driver with kdu, injects
# apexcheat.dll into notepad via --method=kernel, records every step + read-backs, and
# always restores DSE and removes the service (R4). Log: h260_probe.txt (pulled by the host).
$log = 'C:\Users\vboxuser\h260_probe.txt'
function W($t) { ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $t) | Out-File -FilePath $log -Encoding utf8 -Append }
if (Test-Path $log) { Remove-Item $log -Force }

$os  = Get-CimInstance Win32_OperatingSystem
W ('guest ' + $os.Caption + ' build ' + $os.BuildNumber + ' up=' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes + 'min')
W ('ntoskrnl ' + (Get-Item C:\Windows\System32\ntoskrnl.exe).VersionInfo.FileVersion)

$b = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes('C:\Windows\System32\ntoskrnl.exe'))
foreach ($n in @('ZwCreateThreadEx', 'KeInitializeApc', 'KeInsertQueueApc')) {
    W ('export ' + $n + ' = ' + $b.Contains($n))
}

$kdu = @('C:\Users\Public\p37\kdu.exe', 'C:\Users\Public\p37\tools\kdu.exe', 'C:\Users\vboxuser\kdu.exe') |
       Where-Object { Test-Path $_ } | Select-Object -First 1
W ('kdu = ' + $kdu)
if (-not $kdu) { W 'RESULT: FAIL no kdu in guest'; exit 1 }

$sys = 'C:\Users\vboxuser\apexdrv.sys'
W ('sys sha = ' + (Get-FileHash $sys -Algorithm SHA256).Hash)

W ('pre dse = ' + (& $kdu -prv 22 -dse 2>&1 | Out-String).Trim())
if (Get-Service apexdrv -EA 0) { & sc.exe delete apexdrv | Out-Null; Start-Sleep -Milliseconds 500 }
W ('create rc = ' + (& sc.exe create apexdrv type= kernel start= demand binPath= $sys error= normal 2>&1 | Out-String).Trim())

W ('dse off = ' + (& $kdu -prv 22 -dse 0 2>&1 | Out-String).Trim())
W ('start rc = ' + (& sc.exe start apexdrv 2>&1 | Out-String).Trim())
W ('state = ' + ((& sc.exe query apexdrv | Select-String 'STATE') -replace '\s+', ' ').Trim())

$np = Start-Process notepad -PassThru
Start-Sleep -Seconds 3
W ('target notepad pid=' + $np.Id)
$np.Refresh(); W ('target responding=' + $np.Responding)

W '--- launcher ---'
$out = & 'C:\Users\vboxuser\apex_launcher.exe' --inject --method=kernel --pid=$($np.Id) 2>&1
W (($out | Out-String).Trim())
W ('--- exit=' + $LASTEXITCODE)

# module-list read-back: independent of the launcher's own claim
$mod = (Get-Process -Id $np.Id).Modules | Where-Object { $_.ModuleName -eq 'apexcheat.dll' }
W ('module present = ' + [bool]$mod + ' base=' + $(if ($mod) { '0x' + $mod.BaseAddress.ToString('X') } else { '-' }))

W ('restore dse = ' + (& $kdu -prv 22 -dse 22 2>&1 | Out-String).Trim())
W ('stop rc = ' + (& sc.exe stop apexdrv 2>&1 | Out-String).Trim())
W ('delete rc = ' + (& sc.exe delete apexdrv 2>&1 | Out-String).Trim())
Stop-Process -Id $np.Id -Force -EA 0

if ($mod) { W 'RESULT: PASS apexcheat.dll mapped by the APC rung' } else { W 'RESULT: FAIL payload not in module list' }
W 'END'
