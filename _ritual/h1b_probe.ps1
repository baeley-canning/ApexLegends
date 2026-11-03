# h1b - which provider does kdu actually pick on this host, and why did the DSE write fault?
# Non-mutating except the final kdu -dse 6 (writes 6 over 6; may BSOD if the provider is VA-only).
# Captured through cmd redirection so a bugcheck cannot lose the trace.
$o = Join-Path $PSScriptRoot '_h1b.txt'
function W($t){ $t | Add-Content -LiteralPath $o; Write-Host $t }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$pay = 'C:\p37vm\payload'
if(-not $adm){
  Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  exit
}
W ('=== h1b PROVIDER PROBE ' + (Get-Date -f 'dd/MM/yyyy HH:mm:ss') + ' pid=' + $PID + ' ===')
foreach($s in 'DBUtilDrv2','gdrv3','apexdrv'){ W ($s + ' :: ' + (((& sc.exe query $s 2>&1) -join ' ') -replace '\s+',' ')) }

$kdu = $pay + '\kdu.exe'
$cap = $pay + '\_h1b_dse6.txt'
W '## diag (safe, no kernel writes)'
& cmd.exe /c ('"' + $kdu + '" -prv 22 -diag > "' + $pay + '\_h1b_diag.txt" 2>&1')
W ('  rc=' + $LASTEXITCODE)

W '## kdu -prv 22 -dse 6 (write 6 over 6, provider trace)'
& cmd.exe /c ('"' + $kdu + '" -prv 22 -dse 6 > "' + $cap + '" 2>&1')
W ('  rc=' + $LASTEXITCODE)

foreach($s in 'DBUtilDrv2','apexdrv'){ W ($s + ' :: ' + (((& sc.exe query $s 2>&1) -join ' ') -replace '\s+',' ')) }
W '## tail of dse6 capture'
if(Test-Path (Join-Path $pay '_h1b_dse6.txt')){
  W ((Get-Content (Join-Path $pay '_h1b_dse6.txt') | Select-Object -Last 25) -join "`n")
} else { W '  capture missing' }
W '=== END h1b ==='
