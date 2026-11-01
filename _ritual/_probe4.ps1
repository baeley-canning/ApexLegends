# _probe4.ps1 -- attribution harness.  Four arms staged side by side in the CatRoot store; every cycle we
# look up the *exact* driver bytes and log WHICH catalog (if any) answers, for sha1 and sha256.
#   p29ref.cat  = old 806-byte UNSIGNED pscatalog-v2 cat that historically answered sha256  (positive control)
#   p29ctrl.cat = fresh UNSIGNED pristine v2 cat over the driver bytes
#   p29sig.cat  = same pristine cat, signed with the dev cert       (isolates the signature)
#   apexdrv_p26.cat = the broken signed cat already in the store
# Output -> _probe4.txt ; keeps polling ~4 min so index lag cannot be mistaken for a miss.
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_probe4.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
"=== _probe4 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$WORK = 'C:\p26cat'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$pbin = Join-Path $WORK 'p26probe.bin'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)

function Sha([string]$f, [string]$alg) { $h = [Security.Cryptography.HashAlgorithm]::Create($alg); [BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($f))) -replace '-', '' }

L '--- store copy vs source copy of the broken cat ---'
$srcCat = Join-Path $WORK 'apexdrv_p26.cat'
$stCat = Join-Path $CATROOT 'apexdrv_p26.cat'
if (Test-Path -LiteralPath $stCat) {
    L ('store size=' + (Get-Item $stCat).Length + ' src size=' + (Get-Item $srcCat).Length +
        ' samebytes=' + (-not (Compare-Object ([IO.File]::ReadAllBytes($stCat)) ([IO.File]::ReadAllBytes($srcCat)))))
    L ('store copy contains driver sha1 23C73EF9..? ' + (([BitConverter]::ToString([IO.File]::ReadAllBytes($stCat)) -replace '-', '').Contains('23C73EF919F18ECF9855331CF2563D3A15AF52BC')))
    L ('store copy contains driver sha256 37647B46..? ' + (([BitConverter]::ToString([IO.File]::ReadAllBytes($stCat)) -replace '-', '').Contains('37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8')))
} else { L 'broken cat not in store right now' }

function LastC([string]$alg) { ((Get-Content -LiteralPath $ctxt -Tail 20) | Select-String -Pattern ($alg + ' osCatalog=') | Select-Object -Last 1).Line.Trim() }
function Probe([string]$tag, [string]$file) {
    & $cl -Path $file -Lookup 2>&1 | Out-Null
    L ("[$tag] " + (LastC 'sha1'))
    L ("[$tag] " + (LastC 'sha256'))
}

L '--- staging all arms ---'
Remove-Item -LiteralPath (Join-Path $CATROOT 'p29ref.cat'), (Join-Path $CATROOT 'p29un.cat'), (Join-Path $CATROOT 'p29sig.cat') -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 12
$pd = Join-Path $WORK 'p29'
Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $pd -Force | Out-Null
$b1 = Join-Path $WORK 'apexdrv_build.sys'
Copy-Item -LiteralPath $b1 -Destination (Join-Path $pd 'apexdrv_build.sys') -Force
Copy-Item -LiteralPath $b1 -Destination (Join-Path $pd 'apexdrv_sys.sys') -Force
$ctrl = Join-Path $WORK 'p29ctrl.cat'
Remove-Item -LiteralPath $ctrl -Force -ErrorAction SilentlyContinue
New-FileCatalog -Path $pd -CatalogFilePath $ctrl -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null
L ('ctrl size=' + (Get-Item $ctrl).Length + ' sha256=' + (Sha $ctrl 'SHA256'))

# sign a copy
$signtool = @('C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like '*ApexDrv*' } | Select-Object -First 1
$signed = Join-Path $WORK 'p29sig.cat'
Copy-Item -LiteralPath $ctrl -Destination $signed -Force
L ('signtool=' + $signtool + ' cert=' + (@(if ($cert) { $cert.Subject + ' / ' + $cert.Thumbprint } else { 'NONE' })))
& $signtool sign /fd sha256 /sha1 $cert.Thumbprint $signed 2>&1 | ForEach-Object { L ('   signtool: ' + $_) }
L ('signed size=' + (Get-Item $signed).Length + ' sha256=' + (Sha $signed 'SHA256'))

Copy-Item -LiteralPath (Join-Path $WORK 'pr_pscatalog.cat') -Destination (Join-Path $CATROOT 'p29ref.cat') -Force
Copy-Item -LiteralPath $ctrl -Destination (Join-Path $CATROOT 'p29un.cat') -Force
Copy-Item -LiteralPath $signed -Destination (Join-Path $CATROOT 'p29sig.cat') -Force
L 'staged: p29ref.cat / p29un.cat / p29sig.cat (+ preexisting apexdrv_p26.cat)'

L '--- poll loop: which cat answers the driver (37647B46..) and the probe bin (45800E4D..) ---'
for ($i = 1; $i -le 20; $i++) {
    Copy-Item -LiteralPath $ctrl -Destination (Join-Path $CATROOT 'p29un.cat') -Force -ErrorAction SilentlyContinue
    Probe ("c$i drive") $drv
    if ($i % 3 -eq 0) { Probe ("c$i pbin ") $pbin }
    Start-Sleep -Seconds 12
}
L 'END-probe4'
