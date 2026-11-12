# h316 host run - elevated one-shot. Copy of h315_run.ps1 (see cur_h316_live.ps1 for the variable).
# h315's wrapper scored two 1.0 s no-op children (exited at the lock gate) as "host did not
# bugcheck", so this one no longer trusts rc=0: it clears every h316.* gate file itself, measures
# the child's wall time, and reads back $tag.prov + dse_pre before it writes a RESULT.
# If the probe instead dies, the armed logon task is the restore.
# Output: _ritual\h316_pre.txt, durable provider trail C:\Users\Public\p37\h316.prov,
# guest feed at C:\p37vm\guest-h316.log.
#
# Self-elevating: h310_run just failed on admin=False. Relaunch under UAC once and keep every
# later step in the elevated copy; -elevated marks the child so it cannot loop.
param([switch] $elevated)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_pre.txt'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $elevated) {
    Write-Host 'not elevated - relaunching under UAC'
    $ra = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'), '-elevated')
    Start-Process powershell.exe -ArgumentList $ra -Verb RunAs
    exit 0
}
Add-Content -LiteralPath $out -Value ('===== h316 host run ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
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
# the probe exits on the done marker; clear it AND every other gate file of this number, so a
# stale lock (h315's 12-minute rule silently ate two runs) or a leftover .out/.prov cannot make
# this attempt a no-op or mix its evidence with an earlier one.
$d = 'C:\Users\Public\p37'
foreach ($g in 'h316.done', 'h316.lock', 'h316.out', 'h316.prov') { Remove-Item -LiteralPath (Join-Path $d $g) -Force -EA 0 }
Say ('gates cleared: done=' + (Test-Path (Join-Path $d 'h316.done')) + ' lock=' + (Test-Path (Join-Path $d 'h316.lock')) + ' prov=' + (Test-Path (Join-Path $d 'h316.prov')))
Say ('pre hvci=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -EA 0).Enabled + ' vbs=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA 0).EnableVirtualizationBasedSecurity + ' testsigning=' + (bcdedit /enum '{current}' | Select-String 'testsigning' | Out-String).Trim().Replace("`r`n", ' '))
Say ('pre blocklist ci0=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\CI\Config' -EA 0).VulnerableDriverBlocklistEnable)
Say ('pre disk=' + [math]::Round((Get-PSDrive C).Free / 1GB, 1) + 'GB free ram=' + [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) + 'GB uptime=' + [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 1) + 'h')
Say ('pre boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm') + ' build=' + (Get-CimInstance Win32_OperatingSystem).BuildNumber)
Say ('pre exe: cur_h316_live.ps1=' + (Get-Item (Join-Path $here 'cur_h316_live.ps1')).Length + 'B dump-dir=' + $env:SystemRoot)
[Net.ServicePointManager]::Expect100Continue = $false
try { Say ('pre relay: ' + (Invoke-WebRequest "http://127.0.0.1:8080/zapexdrv.sys" -UseBasicParsing -TimeoutSec 10).RawContentLength + 'B') } catch { Say 'pre relay: UNREACHABLE' }

# --- auto-reboot off: a 0x50 must land on a stop screen and keep the dump ----------------
if ($pre.AutoReboot -ne 0) {
    Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 0 -Type DWord
    Say ('AUTO reboot set 0, readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot + ' (was ' + $pre.AutoReboot + ', post restores 1)')
} else { Say 'AUTO reboot already 0, left alone' }

# --- arm the post-restore at logon; it also deletes itself -------------------------------
$cmd = Join-Path $here 'h316_post.cmd'
schtasks.exe /create /tn p316post /tr ('"' + $cmd + '"') /sc onlogon /rl highest /f 2>&1 | ForEach-Object { Say ('arm: ' + $_) }
Say ('arm readback: ' + ((schtasks.exe /query /tn p316post 2>&1) -join ' '))

Say 'RUN probe (h316 chain, TARGET = running r5apex_dx12, Phase 2)'
$t0 = Get-Date
$rc = (Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $here 'cur_h316_live.ps1') + '"') -Wait -PassThru -NoNewWindow).ExitCode
$secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
Say ('probe returned rc=' + $rc + ' after ' + $secs + 's')

# rc=0 is not evidence (R3): a child that dies in the lock/marker gate also exits 0. The verdict
# needs a STEP trail, a dse_pre line or an oracle file from THIS run.
$prov = @(Get-Content (Join-Path $d 'h316.prov') -EA 0)
$outf = Join-Path $d 'h316.out'
$txt  = if (Test-Path $outf) { Get-Content $outf -Raw -EA 0 } else { '' }
$dse  = ([regex]::Match($txt, 'dse_pre=\S+')).Value
$lastProv = if ($prov.Count) { $prov[-1] } else { 'none' }
Say ('child evidence: prov-lines=' + $prov.Count + ' last=[' + $lastProv + '] out-bytes=' + $(if (Test-Path $outf) { (Get-Item $outf).Length } else { 0 }) + ' dse=[' + $dse + ']')
if ($secs -lt 5 -and $prov.Count -eq 0 -and $dse -eq '') {
    Say 'RESULT: NO-OP - child exited in under 5 s with no provider line and no dse_pre (gate, not a probe)'
} elseif ($rc -eq 0) {
    Say ('RESULT: probe returned rc=0 after ' + $secs + 's - host did not bugcheck (evidence above, not the exit code, is the verdict)')
} else {
    Say ('RESULT: probe returned rc=' + $rc + ' after ' + $secs + 's - see h316.out; last provider=' + $lastProv)
}

# --- probe came back: the probe restored itself, this restores the two host-level bits -----
Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 1 -Type DWord
Say ('restore auto-reboot readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot)
schtasks.exe /delete /tn p316post /f 2>&1 | ForEach-Object { Say ('disarm: ' + $_) }
Say ('post svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())
Say ('result line already written above; last provider=' + $lastProv + ' (also in guest-h316.log and h316.prov)')
