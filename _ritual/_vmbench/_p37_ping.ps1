# _p37_ping.ps1 - isolate the 1450 behaviour with the REAL read path
# (GdrvReadOneRaw, which stages into its own page).  Questions, in order:
#   1 does the first call after open work at low and high PA;
#   2 does a 128 KiB call break the handle for the next small call;
#   3 does re-opening the handle recover a broken call;
#   4 is a small read on a good handle stable across repeats.
# Read-only.  Run as SYSTEM via _p37_ping_task2.ps1.
$out = Join-Path $PSScriptRoot '_p37_ping.txt'
function L([string]$s) { Add-Content -LiteralPath $out -Value $s -Encoding ascii }
Set-Content -LiteralPath $out -Value ('ping ' + (Get-Date -f 'HH:mm:ss')) -Encoding ascii
try { Add-Type -Path (Join-Path $PSScriptRoot 'p37_prov.cs') -ErrorAction Stop } catch { L ('compile FAIL ' + $_.Exception.Message); exit }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
if ($e -ne '') { L ('open FAIL ' + $e); exit }
L 'open ok'
$null = [P37Prov]::StageVa
L ('stage va=0x{0:x} locked={1}' -f [P37Prov]::StageVa, [P37Prov]::StageLocked)
function T([uint64]$pa, [int]$n, [string]$tag) {
    $h = ''; $r = 'ok'
    try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, $n); $h = [P37Prov]::Hex($b[0..([Math]::Min(15, $b.Length - 1))]) }
    catch { $r = $_.Exception.Message }
    L ('{0} pa=0x{1:x} n=0x{2:x}: {3} {4}' -f $tag, $pa, $n, $r, $h)
    Start-Sleep -Milliseconds 25
}
T ([uint64]0x1000) 0x20 'A-low'
T ([uint64]0x4000000) 0x20 'A-64M'
T ([uint64]0x12000000) 0x20 'A-tsrc'
T ([uint64]0x4000000) 0x20000 'B-big'
T ([uint64]0x4000000) 0x20 'B-small-after-big'
# reopen, then retry the 128 KiB and a small read on the fresh handle
[P37Prov]::CloseHandle2($g) | Out-Null
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('reopen: ' + $(if ($e -eq '') { 'ok' } else { 'FAIL ' + $e }))
if ($e -eq '') {
    T ([uint64]0x4000000) 0x20000 'C-big-fresh'
    T ([uint64]0x4000000) 0x20 'C-small-fresh'
    T ([uint64]0x100000) 0x1000 'C-page-fresh'
    T ([uint64]0x100000) 0x20 'C-rep1'
    T ([uint64]0x100000) 0x20 'C-rep2'
    T ([uint64]0x100000) 0x20 'C-rep3'
    [P37Prov]::CloseHandle2($g) | Out-Null
}
L 'end'

# other IOCTLs once each on a fresh handle, to record their baseline errors
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
if ($e -eq '') {
    L 'x-codes handle ok'
    $xpg = [P37Prov]::PageAlloc([uint64]0x14000000)
    L ('xpg alloc 0x14000000 -> 0x{0:x}' -f $xpg.ToInt64())
    foreach ($c in 0x2019, 0x2800, 0x280C) {
        $gt = [uint32]0; $er = [uint32]0; $ok = $false
        try {
            if ($c -eq 0x2019) { $q0 = [uint64]0; $q3 = [uint64]0; $dh = ''
                $ok = [P37Prov]::Io2019($g, [uint64]0x100000, 4, [IntPtr]0x14000000, [ref]$q0, [ref]$q3, [ref]$dh, [ref]$gt, [ref]$er) }
            elseif ($c -eq 0x2800) { $a = [uint64]0; $b = [uint64]0; $ok = [P37Prov]::Io2800($g, 0x1000, [ref]$a, [ref]$b, [ref]$gt, [ref]$er) }
            else { $a = [uint64]0; $b = [uint64]0; $ok = [P37Prov]::Io2800($g, 0, [ref]$a, [ref]$b, [ref]$gt, [ref]$er) }
        } catch { $er = 0xFFFF }
        L ('code 0x{0:x}: ok={1} err={2}' -f $c, $ok, $er)
        Start-Sleep -Milliseconds 25
    }
    [P37Prov]::CloseHandle2($g) | Out-Null
}
L 'end'

# and the other IOCTLs once each on ANOTHER fresh handle (the previous $g is closed)
$g = [IntPtr]::Zero
$e2 = [P37Prov]::GdrvOpen([ref]$g)
L ('reopen for second pass: ' + $(if ($e2 -eq '') { 'ok' } else { $e2 }))
foreach ($c in 0x2019, 0x2800, 0x280C) {
    $gt = [uint32]0; $er = [uint32]0
    if ($c -eq 0x2019) { $q0 = [uint64]0; $q3 = [uint64]0; $dh = ''
        $ok = [P37Prov]::Io2019($g, [uint64]0x100000, 4, [IntPtr]0x14000000, [ref]$q0, [ref]$q3, [ref]$dh, [ref]$gt, [ref]$er) }
    elseif ($c -eq 0x2800) { $a = [uint64]0; $b = [uint64]0; $ok = [P37Prov]::Io2800($g, 0x1000, [ref]$a, [ref]$b, [ref]$gt, [ref]$er) }
    else { $a = [uint64]0; $b = [uint64]0; $ok = [P37Prov]::Io2800($g, 0, [ref]$a, [ref]$b, [ref]$gt, [ref]$er) }
    L ('code 0x{0:x}: ok={1} err={2}' -f $c, $ok, $er)
    Start-Sleep -Milliseconds 30
}
[P37Prov]::CloseHandle2($g) | Out-Null
L 'end'
