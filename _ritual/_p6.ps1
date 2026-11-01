# _p6.ps1 -- supersedes the _probe6.ps1 draft. ISOLATED arms, each with its own cryptsvc index pass, so every
# answer is attributed to exactly ONE cat (no name collisions).
#   step 3 = nothing staged        -> does anything else answer at all?
#   step 4 = ONLY p29un.cat        -> fresh UNSIGNED v2 cat over the exact driver bytes
#   step 5 = ONLY apexdrv_p26.cat  -> the SIGNED cat with identical member layout
# Result matrix: unsigned resolves sha256 & signed does not  => signature is the culprit
#                neither resolves sha256                     => member layout is the culprit
#                both resolve                                => it was a stale catdb record all along
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_p6.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
"=== _p6 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$WORK = 'C:\p26cat'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)
L ('catroot exists=' + (Test-Path -LiteralPath $CATROOT))

function LastC([string]$alg) { ((Get-Content -LiteralPath $ctxt -Tail 24) | Select-String -Pattern ($alg + ' osCatalog=') | Select-Object -Last 1).Line.Trim() }
function Probe([string]$tag) {
    & $cl -Path $drv -Lookup 2>&1 | Out-Null
    L ("[$tag] " + (LastC 'sha1'))
    L ("[$tag] " + (LastC 'sha256'))
}
function RestartC {
    try { Restart-Service cryptsvc -Force -EA Stop; L ('  cryptsvc restarted -> ' + (Get-Service cryptsvc).Status) }
    catch { L ('  restart failed: ' + $_.Exception.Message + ' ; state=' + (Get-Service cryptsvc).Status) }
    Start-Sleep -Seconds 8
}
function ClearArms { foreach ($n in @('p29ref.cat', 'p29un.cat', 'p29sig.cat', 'p29sig2.cat')) { Remove-Item -LiteralPath (Join-Path $CATROOT $n) -Force -EA SilentlyContinue } }
function PollArm([string]$tag) { for ($i = 1; $i -le 6; $i++) { Probe ($tag + '-p' + $i); Start-Sleep -Seconds 8 } }

L '--- private-key certs available for signing ---'
foreach ($sn in @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')) {
    foreach ($c in (Get-ChildItem $sn -EA SilentlyContinue | Where-Object { $_.HasPrivateKey })) {
        L ('  ' + $sn + ' ' + $c.Thumbprint + ' ' + $c.Subject + ' notafter=' + $c.NotAfter)
    }
}

L '--- 1. baseline (store as it stands) ---'
Probe 'baseline'

L '--- 2. clear everything, cryptsvc restart ---'
ClearArms
Remove-Item -LiteralPath (Join-Path $CATROOT 'apexdrv_p26.cat') -Force -EA SilentlyContinue
RestartC

L '--- 3. nothing staged: does ANY other store answer? ---'
Probe 'nothing-1'
Start-Sleep -Seconds 8
Probe 'nothing-2'

L '--- 4. ARM A: unsigned v2 cat over the exact driver bytes, ALONE ---'
Copy-Item -LiteralPath (Join-Path $WORK 'p29un.cat') -Destination (Join-Path $CATROOT 'p29un.cat') -Force
RestartC
PollArm 'unsigned'

L '--- 5. ARM B: the SIGNED cat, ALONE ---'
ClearArms
RestartC
Probe 'signed-pre'
Copy-Item -LiteralPath (Join-Path $WORK 'apexdrv_p26.cat') -Destination (Join-Path $CATROOT 'apexdrv_p26.cat') -Force
RestartC
PollArm 'signed'

L 'END-p6'
