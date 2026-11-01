$root='C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev=Join-Path $root 'build\phase1_evidence'
$log='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\st2.txt'
function W([string]$t){ $t | Out-File -Encoding utf8 -Append $log }
"== st2 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$adm=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated : $adm"
W "boot     : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
$bcd=(& cmd /c 'bcdedit /enum {current}' 2>&1 | Out-String).Trim()
W "--- bcdedit EXIT=$LASTEXITCODE ---"
foreach($l in ($bcd -split "`r?`n")){ if($l.Trim()){ W "  $l" } }
W ("TESTSIGNING : " + ($bcd -match 'testsigning\s+Yes'))
$sys=Join-Path $root 'build\apexdrv.sys'
if(Test-Path $sys){ $fi=Get-Item $sys; W "sys      : EXISTS $($fi.Length) B $($fi.LastWriteTime)"; $sv=(& cmd /c "signtool verify /pa /v \"$sys\"" 2>&1 | Out-String); W '--- signtool ---'; foreach($l in ($sv -split "`r?`n")){ if($l.Trim()){ W "  $l" } } } else { W "sys      : MISSING at $sys" }
W '--- sc qc ---'; (& sc.exe qc apexdrv 2>&1)|%{ W "  $_" }
W '--- sc start ---'; (& sc.exe start apexdrv 2>&1)|%{ W "  $_" }
Start-Sleep -Seconds 2
W '--- sc query ---'; (& sc.exe query apexdrv 2>&1)|%{ W "  $_" }
W '--- CodeIntegrity ---'; try{ Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 6 | %{ W ("  {0} id={1} {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, (($_.Message -split "`r`n")[0])) } } catch { W "  $($_.Exception.Message)" }
foreach($f in @('driver_done.txt','post_reboot.txt','kernel_probe.txt','live_state.txt')){ $q=Join-Path $ev $f; if(Test-Path $q){ W "--- EV: $f ---"; Get-Content $q -EA 0 | Select-Object -First 25 | %{ W "  | $_" } } else { W "--- EV MISSING: $f" } }
W 'END'
