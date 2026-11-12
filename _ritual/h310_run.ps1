# h310 host run - elevated one-shot. Host counterpart of the guest tick: pre-state, disarm the
# auto-reboot, arm the post-restore logon task, then run the ported probe (cur_h310_live.ps1) in a
# child process. The probe is expected to die inside STEP=inject-kernel; if it instead returns,
# this script is also the restore for that case. Output: _ritual\h310_pre.txt, and the probe's own
# live feed at C:\p37vm\guest-h310.log.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h310_pre.txt'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
Add-Content -LiteralPath $out -Value ('===== h310 host run ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('admin=' + $admin + ' pid=' + $PID + ' host=' + $env:COMPUTERNAME)
if (-not $admin) { Say 'RESULT: FAIL - not elevated, nothing touched'; exit 1 }

# --- pre-state (R3): everything a later read-back has to be compared against --------------
Say ('pre svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim())
$cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$pre = Get-ItemProperty -LiteralPath $cc
Say ('pre crashcontrol: CrashDumpEnabled=' + $pre.CrashDumpEnabled + ' AutoReboot=' + $pre.AutoReboot + ' AlwaysKeepMemoryDump=' + $pre.AlwaysKeepMemoryDump + ' Overwrite=' + $pre.Overwrite + ' DumpFile=' + $pre.DumpFile)
$dump = Join-Path $env:SystemRoot 'MEMORY.DMP'
Say ('pre dump: exists=' + (Test-Path $dump) + $(if (Test-Path $dump) { ' size=' + (Get-Item $dump).Length + ' written=' + (Get-Item $dump).LastWriteTime.ToString('dd/MM HH:mm:ss') } else { '' }))
Say ('pre minidumps=' + @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count + ' gui=' + @(Get-Process notepad, regedit, mmc -EA 0).Count)
# the probe exits on the done marker; clear it so a repeat run is not a silent no-op
Remove-Item -LiteralPath 'C:\Users\Public\p37\h310.done' -Force -EA 0
Say ('marker cleared, done-exists=' + (Test-Path 'C:\Users\Public\p37\h310.done'))
Say ('pre hvci=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -EA 0).Enabled + ' vbs=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA 0).EnableVirtualizationBasedSecurity + ' testsigning=' + (bcdedit /enum '{current}' | Select-String 'testsigning' | Out-String).Trim().Replace("`r`n", ' '))
Say ('pre blocklist ci0=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\CI\Config' -EA 0).VulnerableDriverBlocklistEnable)
Say ('pre disk=' + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + 'GB free ram=' + [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) + 'GB uptime=' + [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 1) + 'h')
Say ('pre boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm') + ' build=' + (Get-CimInstance Win32_OperatingSystem).BuildNumber)
Say ('pre exe: cur_h310_live.ps1=' + (Get-Item (Join-Path $here 'cur_h310_live.ps1')).Length + 'B dump-dir=' + $env:SystemRoot)
[Net.ServicePointManager]::Expect100Continue = $false
try { Say ('pre relay: ' + (Invoke-WebRequest "http://127.0.0.1:8080/zapexdrv.sys" -UseBasicParsing -TimeoutSec 10).RawContentLength + 'B') } catch { Say 'pre relay: UNREACHABLE' }

# --- auto-reboot off: a 0x50 must land on a stop screen and keep the dump ----------------
if ($pre.AutoReboot -ne 0) {
    Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 0 -Type DWord
    Say ('AUTO reboot set 0, readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot + ' (was ' + $pre.AutoReboot + ', post restores 1)')
} else { Say 'AUTO reboot already 0, left alone' }

# --- arm the post-restore at logon; it also deletes itself -------------------------------
$cmd = Join-Path $here 'h310_post.cmd'
schtasks.exe /create /tn p310post /tr ('"' + $cmd + '"') /sc onlogon /rl highest /f 2>&1 | ForEach-Object { Say ('arm: ' + $_) }
Say ('arm readback: ' + ((schtasks.exe /query /tn p310post 2>&1) -join ' '))

Say 'RUN probe (expect it to die inside STEP=inject-kernel)'
$rc = (Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $here 'cur_h310_live.ps1') + '"') -Wait -PassThru -NoNewWindow).ExitCode
Say ('probe returned rc=' + $rc + ' (no bugcheck)')

# --- probe came back: the probe restored itself, this restores the two host-level bits -----
Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 1 -Type DWord
Say ('restore auto-reboot readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot)
schtasks.exe /delete /tn p310post /f 2>&1 | ForEach-Object { Say ('disarm: ' + $_) }
Say ('post svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())
Say ('RESULT: probe returned rc=' + $rc + ' - host did not bugcheck')
