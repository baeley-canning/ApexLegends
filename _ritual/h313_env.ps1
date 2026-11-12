# h313 T3 - ENV RESTORE + ONE-VARIABLE 1450 DIAGNOSIS. Context measured in h313_pre_state.out:
# the host BUGCHECKED at ~20:17:49 (0x109 CRITICAL_STRUCTURE_CORRUPTION, arg3 0xfffff8073adb2004
# == the CI DSE-flags VA kdu writes, "possibly related driver: CI.dll", dump 110626-10203-01.dmp)
# and rebooted at 20:18:58, so the 20:09-20:18 environment that produced the 1450s is GONE.
# This probe re-establishes parked state, then changes ONE variable: sc create zapexdrv
# (binPath C:\Users\Public\p37\zapexdrv.sys) + sc start - the same start that failed 1450.
# NO DSE WRITE anywhere in this script (kdu -dse with no value = read-only); DSE is re-read
# before and after and reported - the lead decides if a 0 needs restoring to 6.
# DBUtilDrv2: the RUNNING one is the MACHINE's own system service (system32 path, no SCM 7036
# in-window, up since boot 20:18:58, zt2's p37vm instance was unloaded by the bugcheck
# reboot) - it is NOT ours, so per R4 it is left alone and documented, not stopped.
# Restore (R4): everything this script creates (zapexdrv service) is stopped+deleted; zt1 (our
# h312b leftover, STOPPED) is deleted; read-backs after every step. Output: h313_env.out.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h313_env.out'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and $env:H313ENV -ne '1') {
    $env:H313ENV = '1'
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"') -Verb RunAs
    Write-Host 'relaunched elevated'
    exit 0
}
if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }   # own new file (R5)
$t0 = Get-Date
Say ('===== h313 env restore + 1450 one-variable ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' admin=' + $admin + ' pid=' + $PID + ' =====')
$os = Get-CimInstance Win32_OperatingSystem
Say ('boot=' + $os.LastBootUpTime.ToString('dd/MM HH:mm:ss') + ' uptime(min)=' + [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 0))
$game = Get-Process r5apex_dx12 -EA 0
Say ('game r5apex_dx12 pid=' + $(if ($game) { $game.Id } else { 'none' }) + ' (RECORDED ONLY - not touched by this probe)')

function ScQ([string]$svc) {
    ((& "$env:SystemRoot\system32\sc.exe" query $svc 2>&1) -join ' ' -replace '\s+', ' ').Trim()
}
$kduDir = 'C:\Users\Public\p37'
function DseRead([string]$tag) {
    foreach ($id in 22, 0, 1, 2) {
        Push-Location $kduDir
        $ko = & (Join-Path $kduDir 'kdu.exe') -prv $id -dse 2>&1
        Pop-Location
        $flat = ($ko -replace '\s+', ' ').Trim()
        if ($flat -match 'value:\s*([0-9A-Fa-f]+)') {
            Say ('  [' + $tag + '] DSE VALUE=0x' + $matches[1].ToUpper() + ' (read via prv ' + $id + ')')
            return $matches[1].ToUpper()
        }
        Say ('  [' + $tag + '] dse read prv ' + $id + ' no: ' + $flat.Substring(0, [Math]::Min(200, $flat.Length)))
    }
    Say ('  [' + $tag + '] DSE VALUE=UNREADABLE (all of prv 22/0/1/2)')
    return ''
}

Say '--- STEP=pre-state ---'
foreach ($svc in 'zapexdrv', 'apexdrv', 'zt1', 'zt2') { Say ('  pre ' + $svc + ': ' + (ScQ $svc)) }
Say ('  pre DBUtilDrv2: ' + (ScQ 'DBUtilDrv2'))
$dq = & "$env:SystemRoot\System32\driverquery.exe" 2>&1
foreach ($ln in $dq) { if ($ln -match 'DBUtil|zapex|apex|WinRing|NalDrv|AsIO3') { Say ('  pre drv: ' + ($ln -replace '\s+', ' ').Trim()) } }
Say ('  pre bugcheck-dump 110626-10203-01.dmp exists=' + (Test-Path "$env:SystemRoot\Minidump\110626-10203-01.dmp"))
$bc = & "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>&1
foreach ($ln in $bc) { if ($ln -match 'testsigning') { Say ('  pre ' + ($ln -replace '\s+', ' ').Trim()) } }
$perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -EA 0
if ($perf) { Say ('  pre pool: freePhysMB=' + [math]::Round($perf.AvailableMBytes, 0) + ' pagedMB=' + [math]::Round($perf.PoolPagedBytes / 1MB, 1) + ' nonpagedMB=' + [math]::Round($perf.PoolNonpagedBytes / 1MB, 1)) }
$dsePre = DseRead 'pre'
Say ('  DSE pre=0x' + $dsePre + '  (this script performs NO DSE write; parked target is 6, post-reboot default expected)')

Say '--- STEP=cleanup (restore parked state) ---'
foreach ($svc in 'zt1', 'zt2', 'zapexdrv', 'apexdrv') {
    & "$env:SystemRoot\system32\sc.exe" delete $svc 2>&1 | ForEach-Object { Say ('  del ' + $svc + ': ' + ($_ -replace '\s+', ' ').Trim()) }
    Say ('  after del ' + $svc + ': ' + (ScQ $svc))
}

Say '--- STEP=ONE-VARIABLE (sc create zapexdrv + sc start, NO other change) ---'
& "$env:SystemRoot\system32\sc.exe" create zapexdrv type= kernel start= demand binPath= C:\Users\Public\p37\zapexdrv.sys 2>&1 | ForEach-Object { Say ('  create: ' + ($_ -replace '\s+', ' ').Trim()) }
$rc = (Start-Process "$env:SystemRoot\system32\sc.exe" -ArgumentList 'start', 'zapexdrv' -NoNewWindow -Wait -PassThru).ExitCode
Start-Sleep -Milliseconds 600
Say ('  START rc=' + $rc)
Say ('  post query: ' + (ScQ 'zapexdrv'))
$win32 = ''
$q2 = (& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -join ' '
if ($q2 -match 'WIN32_EXIT_CODE\s*:\s*(\d+)') { $win32 = $matches[1] }
Say ('  post WIN32_EXIT_CODE=' + $win32)
$game2 = Get-Process r5apex_dx12 -EA 0
Say ('  game after start: pid=' + $(if ($game2) { $game2.Id } else { 'none' }) + ' alive=' + [bool]$game2)

Say '--- STEP=read-back events (new since ' + $t0.ToString('HH:mm:ss') + ') ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $t0} -EA 0 |
    Where-Object { $_.Message -match 'zapex|apexdrv|zt[12]' } |
    ForEach-Object { Say ('  scm ' + $_.TimeCreated.ToString('HH:mm:ss.fff') + ' id=' + $_.Id + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }
$ci = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 30 -EA 0
$ciNew = @($ci | Where-Object { $_.TimeCreated -ge $t0 })
if ($ciNew.Count -gt 0) {
    foreach ($e in $ciNew) { Say ('  ci ' + $e.TimeCreated.ToString('HH:mm:ss.fff') + ' id=' + $e.Id + ' ' + (($e.Message -replace '\s+', ' ').Trim())) }
} else { Say '  ci: no new CodeIntegrity events since script start' }

Say '--- STEP=restore ---'
if ($rc -eq 0) {
    & "$env:SystemRoot\system32\sc.exe" stop zapexdrv 2>&1 | ForEach-Object { Say ('  stop: ' + ($_ -replace '\s+', ' ').Trim()) }
    Start-Sleep -Milliseconds 600
    Say ('  after stop: ' + (ScQ 'zapexdrv'))
}
& "$env:SystemRoot\system32\sc.exe" delete zapexdrv 2>&1 | ForEach-Object { Say ('  delete: ' + ($_ -replace '\s+', ' ').Trim()) }
Say ('  after delete zapexdrv: ' + (ScQ 'zapexdrv'))
Say ('  final zt1: ' + (ScQ 'zt1') + '  zt2: ' + (ScQ 'zt2'))
$dsePost = DseRead 'post'
Say ('  DSE post=0x' + $dsePost + ' (no DSE write was performed by this script; pre=0x' + $dsePre + ')')
$game3 = Get-Process r5apex_dx12 -EA 0
Say ('  game final: pid=' + $(if ($game3) { $game3.Id } else { 'none' }) + ' alive=' + [bool]$game3)

if ($rc -eq 0) {
    Say 'RESULT: PASS - 1450 NOT reproduced: sc start zapexdrv rc=0 on the post-bugcheck boot (DSE pre=0x' + $dsePre + '), so the 1450 was state from the pre-crash session, not the image; recipe start-step re-runnable'
    Say 'VERDICT: ENV RESTORED + START OK - zapexdrv loads again after the 20:17:49 0x109 (PatchGuard on the DSE-flags VA) reboot flushed the wedged state; h314 may run the full chain (its kdu -dse 0 window is the PatchGuard-risk step - see report)'
} elseif ($rc -eq 577) {
    Say 'RESULT: 1450 NOT reproduced (rc=577 ERROR_INVALID_IMAGE_HASH instead): unsigned zapexdrv under DSE=0x' + $dsePre + ' on a fresh boot fails as a SIGNATURE error, so the 20:09/20:18 1450s (no CI events, DSE read 0x0) were NOT plain signature failures - the reboot cleared them; the chain kdu -dse 0 step is what h314 exercises'
    Say 'VERDICT: ENV RESTORED, 1450 GONE (signature-gate shape now) - recipe re-runnable once its DSE=0 step lands; report to lead with the 0x109 context'
} elseif ($rc -eq 1450) {
    Say ('RESULT: FAIL - 1450 REPRODUCED on the fresh post-bugcheck boot (DSE pre=0x' + $dsePre + ') - the blocker is specific to loading our image and survives a reboot; STOP per brief, no driver edit attempted')
    Say 'VERDICT: FAIL 1450 PERSISTS - diagnose from the scm/ci event lines above + pool numbers; lead decides next (h314 NOT run)'
} else {
    Say ('RESULT: UNEXPECTED rc=' + $rc + ' (WIN32_EXIT_CODE=' + $win32 + ') - neither 0 nor 577 nor 1450; read the event lines above; treat as not-re-runnable until the lead reads h313_env.out')
    Say 'VERDICT: OPEN - unexpected start code; report to lead'
}
