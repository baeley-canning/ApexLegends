$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r '_p38_isp.txt'
Add-Type -Path (Join-Path $r 'p38_prov.cs') -EA Stop
$ramTop = [uint64]0x7f1af1000
[P38Prov]::SetRamRanges('1000-9e000,9f000-a0000,100000-31f52000,35fff000-36000000,100000000-8bfc00000', $ramTop)
$lines = @()
$lines += 'ranges=' + [P38Prov]::RamStarts.Length + '/' + [P38Prov]::RamEnds.Length
$pasList = [uint64[]]@(0x100000, 0x2000000, 0x10000000, 1GB, 2GB, 8GB, 16GB, 24GB, 30GB, 34000000000)
foreach ($p in $pasList) {
    $lines += ('pa=0x{0:x} inRam16={1} inRam4k={2}' -f $p, [P38Prov]::InRamSpanNoBad($p, 0x10000), [P38Prov]::InRamSpanNoBad($p, 0x1000))
}
$pas = $pasList
$lines += 'pas type=' + $pas.GetType().FullName + ' count=' + $pas.Count
try {
    $res = [P38Prov]::ChunkIntegrity([IntPtr]::Zero, $pas)
    $lines += 'integrity returned type=' + $(if ($null -eq $res) { 'NULL' } else { $res.GetType().Name + ' len=' + $res.Length })
    $lines += ($res -split "`r`n")
} catch { $lines += 'integrity EXC: ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message }
$lines | Set-Content -LiteralPath $o -Encoding UTF8
