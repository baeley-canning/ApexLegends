# _p37_diag.ps1 - isolate the "zero try3 lines" mystery: run the exact loop body
# against a bogus handle so no MsIo device is needed, logging every iteration.
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_p37_diag.txt'
Set-Content -LiteralPath $out -Value ('diag start ' + (Get-Date -f 'HH:mm:ss')) -Encoding ascii
function L([string]$s) { Add-Content -LiteralPath $out -Value $s -Encoding ascii }
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'p36_prov.cs') -ErrorAction Stop
    L 'cs loaded'
} catch {
    L ('cs LOAD FAIL: ' + $_.Exception.Message)
    exit 1
}
$mio = [IntPtr]0x1337
$verdict = @{ W2_msio = $false }
$g = [IntPtr]0x1338
foreach ($pa in [uint64]0x20000, [uint64]0x100000, [uint64]0x200000) {
    $e5 = [uint32]0; $vb = [uint64]0; $o2h = [uint64]0; $o4o = [uint64]0; $reg = [IntPtr]::Zero
    $ra = [P36Prov]::MsIoRegionAlloc($pa, [ref]$reg)
    L ("  pre-log check pa=0x{0:x} ra=[{1}] reg=0x{2:x}" -f $pa, $ra, $reg.ToInt64())
    if ($ra -ne '') { L ("  try3 pa=0x{0:x} REGION-ALLOC {1}" -f $pa, $ra); continue }
    try {
        $st3 = [P36Prov]::MsIoMapTry4($mio, $pa, 4, [ref]$e5, [ref]$vb, [ref]$o2h, [ref]$o4o)
        L ("  try3 {0}  view=0x{1:x} h=0x{2:x} obj=0x{3:x}" -f $st3, $vb, $o2h, $o4o)
        if ($o2h -ne 0) { $um = [P36Prov]::MsIoUnmapTry($mio, 4, $pa, $o2h, $vb, $o4o, [ref]$e5); L ("    unmap: {0}" -f $um) }
    } catch {
        L ("  try3 pa=0x{0:x} EXCEPTION: {1}" -f $pa, $_.Exception.Message)
    } finally {
        [P36Prov]::MsIoRegionFree($reg)
    }
    if ($verdict.W2_msio) { break }
}
L 'loop done'
