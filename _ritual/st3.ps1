$root='C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$log='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\st3.txt'
function W($t){ [string]$t | Out-File -Encoding utf8 -Append $log }
"== st3 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$st='C:\ProgramData\QwenKern\apexdrv.sys'; $bd=Join-Path $root 'build\apexdrv.sys'
foreach($f in @($bd,$st)){ if(Test-Path $f){ $fi=Get-Item $f; $sg=Get-AuthenticodeSignature $f; W ("file   : $f  $($fi.Length) B  $($fi.LastWriteTime)  sig=$($sg.Status)  signer=$($sg.SignerCertificate.Subject)") } else { W "file   : $f MISSING" } }
try { W ("secureboot : " + (Confirm-SecureBootUEFI)) } catch { W "secureboot : $($_.Exception.Message)" }
try { $dg=Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard; W ("VBS status=$($dg.VirtualizationBasedSecurityStatus) running=$($dg.SecurityServicesRunning -join ',')") } catch { W "deviceguard: $($_.Exception.Message)" }
W ("lastboot : " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
W ("bcd ts   : " + ((& cmd /c 'bcdedit /enum {current}' 2>&1 | Out-String) -match 'testsigning\s+Yes'))
$signtool='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$cert=Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=ApexDrv Dev (QwenKern Premium)' -and $_.HasPrivateKey } | Select-Object -First 1
if($cert -and (Test-Path $signtool) -and (Test-Path $st)){ & $signtool sign /sm /s My /fd sha256 /sha1 $cert.Thumbprint /v $st 2>&1 | %{ W "  sign| $_" }; W ("resigned sig=" + (Get-AuthenticodeSignature $st).Status) }
if(-not (Get-Service apexdrv -EA 0)){ (sc.exe create apexdrv type= kernel start= demand) 2>&1 | %{ W "  create| $_" } }
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv' -Name ImagePath -Value ('\??\' + $st) -Type ExpandString
try { Start-Service apexdrv } catch { W "start  : $($_.Exception.Message)" }
Start-Sleep -Milliseconds 800
(& sc.exe query apexdrv) | %{ W "  $_" }
W ("loaded : " + ((Get-Service apexdrv -EA 0).Status -eq 'Running'))
W '--- CodeIntegrity ---'
try{ Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 4 | %{ W ("  {0} id={1} {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, (($_.Message -split "`r`n")[0])) } } catch { W "  $($_.Exception.Message)" }
W 'END'
