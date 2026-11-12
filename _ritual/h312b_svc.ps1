# h312b - READ-MOSTLY diagnostic: why does `sc start zapexdrv` return 1450 on a machine that
# started the SAME image 45 min ago (h311)? Two services, each created/started/stopped/deleted in
# this script, no DSE write:
#   t1 = C:\p37vm\payload\zapexdrv.sys  (same bytes, different directory -> excludes the staged path)
#   t2 = C:\p37vm\payload\DbUtilDrv2.sys (unrelated signed driver -> excludes the machine/loader)
# Exit code is not a verdict (R3); the SCM text and the event log are.
# Exit code is not a verdict (R3); the SCM text and the event log are.
# no param block at all: `-File` + a switch aborted the script with 0xFFFD0000 and no output.
$ErrorActionPreference = 'Continue'
$out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'h312b_svc.txt'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
# no param block: -File + a switch aborted with 0xFFFD0000. The sentinel is inherited by the
# elevated child, so it can never relaunch itself in a loop.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and $env:H312B -ne '1') {
    $env:H312B = '1'
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"') -Verb RunAs
    Write-Host 'relaunched elevated'
    exit 0
}
Say ('===== h312b svc diag ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' admin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) + ' =====')

$probes = @(
    @{ name = 'zt1'; path = 'C:\p37vm\payload\zapexdrv.sys' },
    @{ name = 'zt2'; path = 'C:\p37vm\payload\DbUtilDrv2.sys' }
)
foreach ($p in $probes) {
    Say ('--- ' + $p.name + ' ' + $p.path + ' exists=' + (Test-Path $p.path) + ' size=' + (Get-Item $p.path -EA 0).Length)
    Say ('  sha=' + (Get-FileHash $p.path -Algorithm SHA256).Hash.Substring(0, 16))
    & "$env:SystemRoot\system32\sc.exe" delete $p.name 2>&1 | ForEach-Object { Say ('  del: ' + $_) }
    & "$env:SystemRoot\system32\sc.exe" create $p.name type= kernel start= demand binPath= $p.path 2>&1 | ForEach-Object { Say ('  create: ' + $_) }
    $rc = (Start-Process "$env:SystemRoot\system32\sc.exe" -ArgumentList 'start', $p.name -NoNewWindow -Wait -PassThru).ExitCode
    Start-Sleep -Milliseconds 400
    Say ('  start rc=' + $rc)
    Say ('  query: ' + (((& "$env:SystemRoot\system32\sc.exe" query $p.name 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|WIN32_EXIT|does not exist' }) -join ' | ').Trim())
    Start-Sleep -Milliseconds 300
    & "$env:SystemRoot\system32\sc.exe" stop $p.name 2>&1 | Out-Null
    Start-Sleep -Milliseconds 300
    & "$env:SystemRoot\system32\sc.exe" delete $p.name 2>&1 | ForEach-Object { Say ('  del2: ' + $_) }
    Say ('  after: ' + (((& "$env:SystemRoot\system32\sc.exe" query $p.name 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())
}
Say '--- new SCM events (15 min) ---'
Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = (Get-Date).AddMinutes(-15)} -EA 0 |
    Select-Object -First 8 | ForEach-Object { Say ('  ' + $_.TimeCreated.ToString('HH:mm:ss') + ' id=' + $_.Id + ' ' + (($_.Message -replace '\s+', ' ').Trim())) }
Say 'RESULT: diag written - read start rc + event id per service'
