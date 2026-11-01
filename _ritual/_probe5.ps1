# _probe5.ps1 -- attribution harness v2.  Arms staged SIMULTANEOUSLY, all containing the exact driver bytes:
#   p29ref.cat  = the old 806-byte UNSIGNED pscatalog-v2 cat that historically answered a sha256 lookup (control)
#   p29un.cat   = fresh UNSIGNED pristine v2 cat over the driver bytes
#   p29sig2.cat = the SAME cat, signed with the driver's own machine-store signer  <-- isolated variable
#   apexdrv_p26.cat = broken signed cat already in the store
# Each cycle: look up the driver (37647B46..) and log the answering catalog NAME for sha1 and sha256.
# Every 4th cycle also look up p26probe.bin (45800E4D..) so the ref arm proves indexability in-window.
# Output -> _probe5.txt
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_probe5.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8 }
"=== _probe5 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$WORK = 'C:\p26cat'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$pbin = Join-Path $WORK 'p26probe.bin'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)

function LastC([string]$alg) { ((Get-Content -LiteralPath $ctxt -Tail 24) | Select-String -Pattern ($alg + ' osCatalog=') | Select-Object -Last 1).Line.Trim() }
function Probe([string]$tag, [string]$file) {
    & $cl -Path $file -Lookup 2>&1 | Out-Null
    L ("[$tag] " + (LastC 'sha1'))
    L ("[$tag] " + (LastC 'sha256'))
}

$signtool = @('C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
L ('signtool=' + $signtool)

# fresh unsigned ctrl cat over the exact driver bytes
Remove-Item -LiteralPath (Join-Path $CATROOT 'p29ref.cat'), (Join-Path $CATROOT 'p29un.cat'), (Join-Path $CATROOT 'p29sig2.cat') -Force -EA SilentlyContinue
$pd = Join-Path $WORK 'p29'
Remove-Item -LiteralPath $pd -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path $pd -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $WORK 'apexdrv_build.sys') -Destination (Join-Path $pd 'apexdrv_build.sys') -Force
Copy-Item -LiteralPath (Join-Path $WORK 'apexdrv_build.sys') -Destination (Join-Path $pd 'apexdrv_sys.sys') -Force
$ctrl = Join-Path $WORK 'p29un.cat'
Remove-Item -LiteralPath $ctrl -Force -EA SilentlyContinue
New-FileCatalog -Path $pd -CatalogFilePath $ctrl -CatalogVersion 2 -EA SilentlyContinue | Out-Null
L ('ctrl size=' + (Get-Item $ctrl).Length)

# isolate the signature: sign the very same bytes with the driver's own signer (machine store)
$thumb = (Get-AuthenticodeSignature -LiteralPath $drv).SignerCertificate.Thumbprint
$signed = Join-Path $WORK 'p29sig2.cat'
Copy-Item -LiteralPath $ctrl -Destination $signed -Force
L ('driver signer thumb=' + $thumb)
& $signtool sign /v /fd sha256 /sm /sha1 $thumb $signed 2>&1 | ForEach-Object { L ('   sign/sm: ' + $_) }
if ((Get-Item $signed).Length -eq (Get-Item $ctrl).Length) {
    L '   (size unchanged -> retry without /sm)'
    & $signtool sign /v /fd sha256 /sha1 $thumb $signed 2>&1 | ForEach-Object { L ('   sign: ' + $_) }
}
L ('signed size=' + (Get-Item $signed).Length + ' (unsigned was ' + (Get-Item $ctrl).Length + ')')
L ('signed status=' + (Get-AuthenticodeSignature -LiteralPath $signed).Status)

Copy-Item -LiteralPath (Join-Path $WORK 'pr_pscatalog.cat') -Destination (Join-Path $CATROOT 'p29ref.cat') -Force
Copy-Item -LiteralPath $ctrl -Destination (Join-Path $CATROOT 'p29un.cat') -Force
Copy-Item -LiteralPath $signed -Destination (Join-Path $CATROOT 'p29sig2.cat') -Force
L 'staged p29ref.cat (unsigned 806, historical HIT) / p29un.cat (unsigned) / p29sig2.cat (SIGNED) / apexdrv_p26.cat (signed, broken)'

L '--- poll loop ---'
for ($i = 1; $i -le 20; $i++) {
    Copy-Item -LiteralPath $ctrl -Destination (Join-Path $CATROOT 'p29un.cat') -Force -EA SilentlyContinue
    Copy-Item -LiteralPath $signed -Destination (Join-Path $CATROOT 'p29sig2.cat') -Force -EA SilentlyContinue
    Probe ("c$i drive") $drv
    if ($i % 4 -eq 0) { Probe ("c$i pbin ") $pbin }
    Start-Sleep -Seconds 10
}
L 'END-probe5'
