# _probe3.ps1 -- is apexdrv_p26.cat identical to a pristine New-FileCatalog v2 output over the same
# filenames/bytes?  If not, the hand-rolled post-processing (or the signing step) is what broke the
# 32-byte member keys.  Also: stage a pristine control cat and see if the real driver's SHA-256
# lookup resolves through it while the current cat's does not.  Output -> _probe3.txt
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_probe3.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
"=== _probe3 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$walk = Join-Path $PSScriptRoot '_catwalk.ps1'
$WORK = 'C:\p26cat'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated=' + $elev)

function LastLook([string]$alg) { ((Get-Content -LiteralPath $ctxt -Tail 20) | Select-String -Pattern ($alg + ' osCatalog=') | Select-Object -Last 1).Line.Trim() }
function Snapshot([string]$tag) {
    & $cl -Path $drv -Lookup 2>&1 | Out-Null
    L ("[$tag] " + (LastLook 'sha1'))
    L ("[$tag] " + (LastLook 'sha256'))
}
function Flush() { if ($elev) { try { Restart-Service cryptsvc -Force -ErrorAction Stop } catch { } ; Start-Sleep -Seconds 4 } else { Start-Sleep -Seconds 20 } }

L '--- 0. working dir contents ---'
Get-ChildItem -LiteralPath $WORK | ForEach-Object { L ('   ' + $_.Name + '  ' + $_.Length + '  ' + $_.LastWriteTime.ToString('s')) }

L '--- 1. baselines (driver hashes via cateng, store state) ---'
& $cl -Path $drv -Lookup 2>&1 | Out-Null
$tail = Get-Content -LiteralPath $ctxt -Tail 6
$tail | ForEach-Object { L ('   ' + $_) }
$h1 = ((($tail | Select-String -Pattern 'sha1 engine=([0-9A-F]{40})').Matches)[0].Groups[1].Value)
$h2 = ((($tail | Select-String -Pattern 'sha256 engine=([0-9A-F]{64})').Matches)[0].Groups[1].Value)
L ("driver sha1=$h1")
L ("driver sha256=$h2")

L '--- 2. build pristine control cat over the same two filenames ---'
$pd = Join-Path $WORK 'p29'
Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $pd -Force | Out-Null
$src1 = Join-Path $WORK 'apexdrv_build.sys'
$src2 = Join-Path $WORK 'apexdrv_sys.sys'
if (-not (Test-Path -LiteralPath $src1)) { $src1 = $drv }
Copy-Item -LiteralPath $src1 -Destination (Join-Path $pd 'apexdrv_build.sys') -Force
if (Test-Path -LiteralPath $src2) { Copy-Item -LiteralPath $src2 -Destination (Join-Path $pd 'apexdrv_sys.sys') -Force } else { Copy-Item -LiteralPath $src1 -Destination (Join-Path $pd 'apexdrv_sys.sys') -Force }
$ctrl = Join-Path $WORK 'p29ctrl.cat'
Remove-Item -LiteralPath $ctrl -Force -ErrorAction SilentlyContinue
New-FileCatalog -Path $pd -CatalogFilePath $ctrl -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null
$cur = Join-Path $WORK 'apexdrv_p26.cat'
if (Test-Path -LiteralPath $ctrl) {
    $cb = [IO.File]::ReadAllBytes($ctrl); $pb = [IO.File]::ReadAllBytes($cur)
    L ('ctrl size=' + $cb.Length + '  current size=' + $pb.Length + '  identical=' + (($cb.Length -eq $pb.Length) -and (-not (Compare-Object $cb $pb))))
    & $walk -Cat $ctrl -Depth 12 -Out (Join-Path $PSScriptRoot '_catwalk_ctrl.txt') 2>&1 | Out-Null
    & $walk -Cat $cur -Depth 12 -Out (Join-Path $PSScriptRoot '_catwalk_now.txt') 2>&1 | Out-Null
    L ("ctrl  member-ids: " + (((Get-Content -LiteralPath (Join-Path $PSScriptRoot '_catwalk_ctrl.txt')) | Select-String 'UP-OCTSTR' | ForEach-Object { $_.Line.Trim() }) -join ' | '))
    L ("now   member-ids: " + (((Get-Content -LiteralPath (Join-Path $PSScriptRoot '_catwalk_now.txt')) | Select-String 'UP-OCTSTR' | ForEach-Object { $_.Line.Trim() }) -join ' | '))
    L ("ctrl/now contain driver-sha256? ctrl=" + (([BitConverter]::ToString($cb) -replace '-','').Contains($h2)) + " now=" + (([BitConverter]::ToString($pb) -replace '-','').Contains($h2)))
} else { L 'control cat NOT built' }

L '--- 3. stage UNSIGNED control, wait, lookup real driver ---'
$staged = Join-Path $CATROOT 'p29ctrl.cat'
Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $ctrl -Destination $staged -Force
Flush
Snapshot 'unsigned-ctrl'

L '--- 4. sign the control cat with the dev cert, re-stage, lookup ---'
$signtool = @(
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
L ('signtool=' + $signtool)
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like '*ApexDrv*' } | Select-Object -First 1
L ('cert=' + (@(if ($cert) { $cert.Subject + ' / ' + $cert.Thumbprint } else { 'NONE' })))
if ($signtool -and $cert) {
    $signed = Join-Path $WORK 'p29ctrl_signed.cat'
    Copy-Item -LiteralPath $ctrl -Destination $signed -Force
    & $signtool sign /fd sha256 /sha1 $cert.Thumbprint $signed 2>&1 | ForEach-Object { L ('   signtool: ' + $_) }
    if (Test-Path -LiteralPath $signed) { L ('signed size=' + (Get-Item $signed).Length) }
    Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $signed -Destination (Join-Path $CATROOT 'p29ctrl.cat') -Force
    Flush
    Snapshot 'signed-ctrl'
}
L '--- 5. cleanup: remove control cat from store, confirm driver back to baseline ---'
Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
Flush
Snapshot 'after-removal'
L 'END-probe3'
