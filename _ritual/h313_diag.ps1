# h313 diag - READ-ONLY follow-up to h313_env.out (1450 reproduced at 20:41:15). The env
# probe's DseRead helper lost the per-provider kdu output (a Substring-on-array defect), so
# the one missing datum is: what do kdu's provider loads print on THIS boot, and can any
# provider read the DSE flags at all. This script runs ONLY `kdu -prv <id> -dse` (no value
# argument = read-only, same step T1/the cur_ chains use; each run loads+unloads kdu's own
# signed provider transiently) and captures the output VERBATIM. No sc create/start/stop,
# no DSE write, no process kill. Output: h313_diag.out (own new file, R5).
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h313_diag.out'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and $env:H313DIAG -ne '1') {
    $env:H313DIAG = '1'
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"') -Verb RunAs
    Write-Host 'relaunched elevated'
    exit 0
}
if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
$t0 = Get-Date
Say ('===== h313 diag (read-only kdu provider survey) ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' admin=' + $admin + ' pid=' + $PID + ' =====')
Say ('boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm:ss'))
Say ('game r5apex_dx12 pid=' + $(if ($g = Get-Process r5apex_dx12 -EA 0) { $g.Id } else { 'none' }) + ' (recorded only)')

$kduDir = 'C:\Users\Public\p37'
$dseVal = ''
foreach ($id in 22, 0, 1, 2, 3) {
    Say ('--- kdu -prv ' + $id + ' -dse (read-only) ---')
    Push-Location $kduDir
    $ko = & (Join-Path $kduDir 'kdu.exe') -prv $id -dse 2>&1
    $rc = $LASTEXITCODE
    Pop-Location
    Say ('  kdu rc=' + $rc + ' lines=' + @($ko).Count)
    foreach ($ln in @($ko)) {
        $t = "$ln".Trim()
        if ($t -ne '') { Say ('  | ' + $t) }
    }
    $flat = (@($ko) -join ' ') -replace '\s+', ' '
    if ($flat -match 'DSE flags \(([^)]*)\)\s*value:\s*([0-9A-Fa-f]+)') {
        $dseVal = $matches[2].ToUpper()
        Say ('  => DSE VALUE=0x' + $dseVal + ' via prv ' + $id)
        break
    } else {
        Say ('  => no DSE-flags value in prv ' + $id + ' output')
    }
}
Say ('DSE-now=' + $(if ($dseVal) { '0x' + $dseVal } else { 'UNREADABLE on this boot via prv 22/0/1/2/3' }))
Say '--- events since diag start (SCM zapex/kdu-provider names + CodeIntegrity) ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $t0} -EA 0 |
    Where-Object { $_.Message -match 'zapex|NalDrv|RTCore|Gdrv|ATSZIO|AsIO3|WinRing' } |
    ForEach-Object { Say ('  scm ' + $_.TimeCreated.ToString('HH:mm:ss.fff') + ' id=' + $_.Id + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }
$ci = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 10 -EA 0
$ciNew = @($ci | Where-Object { $_.TimeCreated -ge $t0 })
if ($ciNew.Count -gt 0) { foreach ($e in $ciNew) { Say ('  ci ' + $e.TimeCreated.ToString('HH:mm:ss.fff') + ' id=' + $e.Id + ' ' + (($e.Message -replace '\s+', ' ').Trim())) } }
else { Say '  ci: no new CodeIntegrity events during this diag' }
Say '--- bugcheck context (for the record, from the 20:19:05 BugCheck 1001) ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddHours(-2)} -EA 0 |
    ForEach-Object { Say ('  ' + $_.TimeCreated.ToString('HH:mm:ss') + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }
Say ('RESULT: diag written - kdu provider outputs verbatim above; DSE-now=' + $(if ($dseVal) { '0x' + $dseVal } else { 'UNREADABLE' }) + '; no mutation (providers load+unload inside kdu only)')
Say 'VERDICT: DIAG - read h313_diag.out: if a provider read DSE=6, the 20:41 1450 is unsigned-under-DSE6 on build 26200 (recipe needs its kdu -dse 0 step to land = h314); if DSE=0, 1450 is a deeper kernel loader issue; if UNREADABLE, provider I/O on this boot is degraded (AsIO3 read err 483 at 20:36)'
