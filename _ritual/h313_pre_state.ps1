# h313 T1 - PRE-STATE READ-BACK, no mutation (R3/R6). Everything later probes will be judged
# against: services (zapexdrv/apexdrv/zt1/zt2/DBUtilDrv2/NalDrv), driverquery residency,
# DSE via the same kdu -prv 22 -dse read step the cur_ chains use (run from C:\Users\Public\p37
# so drv64.dll resolves; read-only: NO value argument, kdu loads WinRing0, prints, unloads),
# bcdedit testsigning, leftover game/notepad/regedit processes, hashes of every image the rung
# will touch, recent SCM + CodeIntegrity events, leftover scheduled tasks.
# Output: _ritual\h313_pre_state.out. No service create/start/stop, no DSE write, no file swap.
# Self-elevating: no param block (-File + a switch aborted with 0xFFFD0000 in h312b); the env
# sentinel is inherited by the elevated child so it cannot loop.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h313_pre_state.out'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and $env:H313PRE -ne '1') {
    $env:H313PRE = '1'
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"') -Verb RunAs
    Write-Host 'relaunched elevated'
    exit 0
}
if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }   # own new file each run (R5)
Say ('===== h313 pre-state read-back ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' admin=' + $admin + ' pid=' + $PID + ' host=' + $env:COMPUTERNAME + ' =====')
$os = Get-CimInstance Win32_OperatingSystem
Say ('boot=' + $os.LastBootUpTime.ToString('dd/MM HH:mm') + ' build=' + $os.BuildNumber + ' uptime(h)=' + [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1))

Say '--- STEP=services (sc query) ---'
foreach ($svc in 'zapexdrv', 'apexdrv', 'zt1', 'zt2', 'DBUtilDrv2', 'NalDrv') {
    $q = (& "$env:SystemRoot\system32\sc.exe" query $svc 2>&1) -join ' '
    Say ('  ' + $svc + ': ' + (($q -replace '\s+', ' ').Trim()))
}
Say '--- sc qc DBUtilDrv2 (system service config: ours or the machine own?) ---'
foreach ($ln in (& "$env:SystemRoot\system32\sc.exe" qc DBUtilDrv2 2>&1)) { if ($ln.Trim() -ne '') { Say ('  | ' + $ln.TrimEnd()) } }
Say '--- Win32_SystemDriver objects matching our names ---'
Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'zapex|apexdrv|^zt[12]$|DBUtil|WinRing|NalDrv' } |
    ForEach-Object { Say ('  svc=' + $_.Name + ' state=' + $_.State + ' startMode=' + $_.StartMode + ' path=' + $_.PathName) }

Say '--- STEP=driverquery residency (DBUtilDrv2 / zapex / apex / WinRing0 / NalDrv) ---'
$dq = & "$env:SystemRoot\System32\driverquery.exe" 2>&1
foreach ($ln in $dq) { if ($ln -match 'DBUtil|zapex|apex|WinRing|NalDrv') { Say ('  | ' + ($ln -replace '\s+', ' ').Trim()) } }
if (-not ($dq | Where-Object { $_ -match 'DBUtil|zapex|WinRing|NalDrv' })) { Say '  (no matching rows)' }

Say '--- STEP=dse-read (kdu -prv 22 -dse, read-only, from C:\Users\Public\p37) ---'
$kduDir = 'C:\Users\Public\p37'
Push-Location $kduDir
$kduOut = & (Join-Path $kduDir 'kdu.exe') -prv 22 -dse 2>&1
Pop-Location
$kduFlat = ($kduOut -replace '\s+', ' ').Trim()
Say ('  kdu rc=' + $LASTEXITCODE)
foreach ($ln in $kduOut) {
    $t = $ln.Trim()
    if ($t -ne '' -and $t -match 'value:|provider|loaded|unloaded|Return value|error|failed') { Say ('  | ' + $t) }
}
if ($kduFlat -match 'DSE flags \(([^)]*)\)\s*value:\s*([0-9A-Fa-f]+)') {
    Say ('  DSE flags addr=' + $matches[1] + ' VALUE=0x' + $matches[2].ToUpper())
} elseif ($kduFlat -match 'value:\s*([0-9A-Fa-f]+)') {
    Say ('  DSE VALUE=0x' + $matches[1].ToUpper() + ' (addr not parsed)')
} else {
    Say '  DSE VALUE=UNREADABLE via prv 22'
}

Say '--- STEP=bcdedit testsigning ---'
$bc = & "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' 2>&1
foreach ($ln in $bc) { if ($ln -match 'testsigning|hypervisorlaunchtype|signing') { Say ('  | ' + ($ln -replace '\s+', ' ').Trim()) } }
Say ('  testsigning-line-present=' + [bool]($bc | Where-Object { $_ -match 'testsigning' }))

Say '--- STEP=leftover processes (game/notepad/regedit/mmc/launcher) ---'
foreach ($pn in 'r5apex', 'r5apex_dx12', 'notepad', 'regedit', 'mmc', 'apex_launcher', 'EasyAntiCheat') {
    $g = @(Get-Process $pn -EA 0)
    Say ('  ' + $pn + ' count=' + $g.Count + $(if ($g.Count -gt 0) { ' pids=' + (($g | ForEach-Object { $_.Id }) -join ',') }))
}

Say '--- STEP=image hashes the rung will touch ---'
foreach ($f in 'C:\Users\Public\p37\zapexdrv.sys', 'C:\Users\Public\p37\kdu.exe', 'C:\Users\Public\p37\apex_launcher.exe', 'C:\Users\Public\p37\apexcheat.dll', 'C:\Users\Public\p37\pe_tls.ps1', 'C:\Users\Public\apxprobe.dll', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat.dll', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apex_launcher.exe', 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys') {
    if (Test-Path -LiteralPath $f) {
        $it = Get-Item -LiteralPath $f
        Say ('  ' + $f + ' size=' + $it.Length + ' mt=' + $it.LastWriteTime.ToString('dd/MM HH:mm:ss') + ' sha256=' + (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash)
    } else { Say ('  ' + $f + ' MISSING') }
}

Say '--- STEP=recent SCM events (3 h, ids 7000/7045/7036 zapex/zt/apex/DBUtil only) ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = (Get-Date).AddHours(-3)} -EA 0 |
    Where-Object { $_.Message -match 'zapex|apexdrv|^zt[12]|zt1|zt2|DBUtil|NalDrv' } |
    Select-Object -First 25 |
    ForEach-Object { Say ('  ' + $_.TimeCreated.ToString('HH:mm:ss') + ' id=' + $_.Id + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }
Say '--- DBUtilDrv2 7036 history (12 h): boot-time or today-window? ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7036; StartTime = (Get-Date).AddHours(-12)} -EA 0 |
    Where-Object { $_.Message -match 'DBUtilDrv2' } |
    Select-Object -First 10 |
    ForEach-Object { Say ('  ' + $_.TimeCreated.ToString('dd/MM HH:mm:ss') + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }

Say '--- STEP=CodeIntegrity operational events (3 h) ---'
$ci = Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 20 -EA 0
if ($ci) {
    foreach ($e in $ci) { Say ('  ' + $e.TimeCreated.ToString('HH:mm:ss') + ' id=' + $e.Id + ' ' + (($e.Message -replace '\s+', ' ').Trim())) }
} else { Say '  (log empty or absent)' }

Say '--- STEP=leftover scheduled tasks ---'
foreach ($tn in 'p310go', 'p312post', 'p313post') {
    $t = schtasks.exe /query /tn $tn 2>&1
    Say ('  ' + $tn + ': ' + (($t -join ' ') -replace '\s+', ' ').Trim())
}

Say '--- pool/memory snapshot (1450 context: ERROR_NO_SYSTEM_RESOURCES) ---'
$perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -EA 0
if ($perf) {
    Say ('  freePhysMB=' + [math]::Round($perf.AvailableMBytes, 0) + ' poolPagedMB=' + [math]::Round($perf.PoolPagedBytes / 1MB, 1) + ' poolNonpagedMB=' + [math]::Round($perf.PoolNonpagedBytes / 1MB, 1) + ' commitGB=' + [math]::Round($perf.CommittedBytes / 1GB, 1) + '/' + [math]::Round($perf.CommitLimit / 1GB, 1))
}
Say ('  svchost=' + @(Get-Process svchost -EA 0).Count + ' handles(proc4)=' + (Get-Process -Id 4).HandleCount)

Say 'RESULT: h313 pre-state read-back written - NO mutation performed (sc query/driverquery/kdu read/bcdedit enum/process list/events only)'
Say 'VERDICT: PRE - read the file: DSE value line, DBUtilDrv2 state + 7036 history, service leftovers, process leftovers decide the T3 cleanup'
