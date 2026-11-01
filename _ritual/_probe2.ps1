# _probe2.ps1 -- controlled test: does a freshly New-FileCatalog -CatalogVersion 2 cat answer a
# 32-byte (sha256) store lookup?  Structure: build probe file -> cat -> stage in CatRoot -> lookup
# with cateng (both algs) -> remove cat -> lookup again (proves no stale hit).  Output -> _probe2.txt
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_probe2.txt'
function L($s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
"=== _probe2 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $out
$cl = Join-Path $PSScriptRoot 'cateng.ps1'
$ctxt = Join-Path $PSScriptRoot 'cateng.txt'
$WORK = 'C:\p26cat'
$CATROOT = Join-Path $env:SystemRoot 'System32\CatRoot\{F750E6C3-38EE-11D1-85E5-00C04FC295EE}'
$pd = Join-Path $WORK 'p28'
$pf = Join-Path $pd 'p28probe.bin'
$cat = Join-Path $WORK 'p28pr.cat'
$inStore = Join-Path $CATROOT 'p28pr.cat'

Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $pd -Force | Out-Null
Set-Content -LiteralPath $pf -Value ('p28 probe ' + [Guid]::NewGuid().ToString()) -Encoding ascii
Remove-Item -LiteralPath $cat -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $inStore -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ---- A: baseline, cat NOT in store
& $cl -Path $pf -Lookup 2>&1 | Out-Null
L ('A no-cat-in-store  : ' + ((Get-Content -LiteralPath $ctxt -Tail 4) -join ' || '))

# ---- B: build a pscatalog v2 cat and stage it
New-FileCatalog -Path $pd -CatalogFilePath $cat -CatalogVersion 2 -ErrorAction SilentlyContinue | Out-Null
L ("B built cat exists={0} size={1} gen=v2" -f (Test-Path $cat), (@(if (Test-Path $cat) { (Get-Item $cat).Length } else { 0 })))
if (Test-Path $cat) {
    & (Join-Path $PSScriptRoot '_catwalk.ps1') -Cat $cat -Depth 8 -Out '_catwalk_probe.txt' 2>&1 | Out-Null
    Copy-Item -LiteralPath $cat -Destination $inStore -Force
    Start-Sleep -Seconds 15
    & $cl -Path $pf -Lookup 2>&1 | Out-Null
    L ('C cat-in-store(15s) : ' + ((Get-Content -LiteralPath $ctxt -Tail 4) -join ' || '))
    $elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    L ('elevated=' + $elev)
    if ($elev) {
        try { Restart-Service cryptsvc -Force -ErrorAction Stop; L 'cryptsvc restarted' } catch { L ('cryptsvc restart FAILED: ' + $_.Exception.Message) }
        Start-Sleep -Seconds 5
        & $cl -Path $pf -Lookup 2>&1 | Out-Null
        L ('C2 after-flush      : ' + ((Get-Content -LiteralPath $ctxt -Tail 4) -join ' || '))
    }
    Remove-Item -LiteralPath $inStore -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15
    & $cl -Path $pf -Lookup 2>&1 | Out-Null
    L ('D cat-removed      : ' + ((Get-Content -LiteralPath $ctxt -Tail 4) -join ' || '))
}
# ---- E: control -- the real staged cat still resolves at sha1 only?
$real = 'C:\Windows\System32\drivers\apexdrv.sys'
if (Test-Path -LiteralPath $real) {
    & $cl -Path $real -Lookup 2>&1 | Out-Null
    L ('E real-driver      : ' + ((Get-Content -LiteralPath $ctxt -Tail 4) -join ' || '))
}
L 'END-probe2'
