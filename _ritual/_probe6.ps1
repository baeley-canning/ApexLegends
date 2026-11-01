# _probe6.ps1 -- decisive: is the sha1-hit/sha256-miss caused by a STALE catdb record, or by the cat itself?
# Sequence: baseline -> remove cat + restart cryptsvc -> lookups -> re-add same file + restart -> lookups -> poll.
# Plus: enumerate any cert with a private key so the signed arm can actually be built.
# Output -> _probe6.txt
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_probe6.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
"=== _probe6 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$DB = Join-Path $env:SystemRoot 'System32\catroot2\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$WORK = 'C:\p26cat'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)
L ('catroot=' + $CATROOT + '  exists=' + (Test-Path -LiteralPath $CATROOT))
L ('catdb dir=' + $DB + '  exists=' + (Test-Path -LiteralPath $DB))

function LastC([string]$alg) { ((Get-Content -LiteralPath $ctxt -Tail 24) | Select-String -Pattern ($alg + ' osCatalog=') | Select-Object -Last 1).Line.Trim() }
function Probe([string]$tag) {
    & $cl -Path $drv -Lookup 2>&1 | Out-Null
    L ("[$tag] " + (LastC 'sha1'))
    L ("[$tag] " + (LastC 'sha256'))
}

L '--- private-key certs available for signing ---'
foreach ($sn in @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')) {
    foreach ($c in (Get-ChildItem $sn -EA SilentlyContinue | Where-Object { $_.HasPrivateKey })) {
        L ('  ' + $sn + ' ' + $c.Thumbprint + ' ' + $c.Subject + ' notafter=' + $c.NotAfter)
    }
}
$signtool = @('C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

L '--- 1. baseline ---'
Probe 'baseline'

L '--- 2. remove apexdrv_p26.cat from the store and restart cryptsvc ---'
$stCat = Join-Path $CATROOT 'apexdrv_p26.cat'
Remove-Item -LiteralPath $stCat -Force -EA SilentlyContinue
L ('removed? ' + (-not (Test-Path -LiteralPath $stCat)))
$rg = Get-Service cryptsvc
L ('cryptsvc before=' + $rg.Status + ' starttype=' + $rg.StartType)
try { Restart-Service cryptsvc -Force -EA Stop; L 'Restart-Service cryptsvc OK' } catch { L ('Restart-Service failed: ' + $_.Exception.Message) }
Start-Sleep -Seconds 8
L ('cryptsvc after=' + (Get-Service cryptsvc).Status)
Probe 'no-cat'

L '--- 3. re-add the SAME file, restart cryptsvc, let it re-index ---'
Copy-Item -LiteralPath (Join-Path $WORK 'apexdrv_p26.cat') -Destination $stCat -Force
L ('re-added size=' + (Get-Item $stCat).Length)
try { Restart-Service cryptsvc -Force -EA Stop; L 'Restart-Service cryptsvc OK (2)' } catch { L ('Restart-Service failed (2): ' + $_.Exception.Message) }
Start-Sleep -Seconds 8
L ('cryptsvc after2=' + (Get-Service cryptsvc).Status)

for ($i = 1; $i -le 9; $i++) {
    Probe ("readd-c$i")
    Start-Sleep -Seconds 8
}
L 'END-probe6'
