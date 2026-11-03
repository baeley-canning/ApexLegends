# _p37_probe.ps1 - elevated ground truth for the S1 candidate predicate.
# 1) are reads returning real bytes at mid/high PA?
# 2) does any page in 256 MB..1 GB carry a self-referencing 0x1ED entry
#    (the exact test ScanPml4 uses), or a present entry at all?
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot '_p37_probe.out'
Remove-Item -LiteralPath $out -EA 0
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null; $s }
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'p37_prov.cs')
    L 'compiled OK'
} catch { L ('COMPILE FAILED: ' + $_.Exception.Message); $log -join "`r`n" | Out-File $out -Encoding UTF8; exit 1 }
[P37Prov]::SetRamRanges('1000-9e000,9f000-a0000,100000-31f52000,35fff000-36000000,100000000-8bfc00000', [uint64]0x800000000)
$g = [IntPtr]::Zero
$eo = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $eo + ' h=0x{0:x}' -f $g.ToInt64())
if ($eo -ne '') { $log -join "`r`n" | Out-File $out -Encoding UTF8; exit 1 }
foreach ($pa in [uint64]0x1000, [uint64]0x12000000, [uint64]0x1A000000, [uint64]0x30000000, [uint64]0x40000000, [uint64]0x100000000, [uint64]0x200000000, [uint64]0x600000000) {
    try {
        $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x1000)
        $nz = 0
        for ($i = 0; $i -lt 4096; $i++) { if ($b[$i] -ne 0) { $nz++ } }
        L ('sample pa=0x{0:x} nonzero={1} head={2}' -f $pa, $nz, [P37Prov]::Hex(($b[0..7])))
    } catch { L ('sample pa=0x{0:x} ERR {1}' -f $pa, $_.Exception.Message) }
}
# predicate sweep: entry 0x1ED per page
$self = 0; $present = 0; $hits = @()
$t0 = Get-Date
for ($pa = [uint64]0x10000000; $pa -lt [uint64]0x40000000; $pa += 0x10000) {
    try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x10000) } catch { continue }
    for ($o = 0; $o -lt 0x10000; $o += 0x1000) {
        $ev = [BitConverter]::ToUInt64($b, $o + 0x1ED * 8)
        $page = $pa + [uint64]$o
        if (($ev -band 1) -ne 0) { $present++ }
        if ((($ev -band 0x000FFFFFFFFFF000L) -eq $page) -and $ev -ne 0) {
            $self++
            if ($hits.Count -lt 8) { $hits += ('0x{0:x} entry=0x{1:x}' -f $page, $ev) }
        }
    }
}
L ('sweep 0x10000000-0x40000000: pages_with_present_1ED={0} self_referencing={1} in {2:N1}s' -f $present, $self, ((Get-Date) - $t0).TotalSeconds)
foreach ($h in $hits) { L ('  hit ' + $h) }
$log -join "`r`n" | Out-File -LiteralPath $out -Encoding UTF8
