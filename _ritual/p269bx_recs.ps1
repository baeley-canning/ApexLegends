# p269bx: the structure at 0x1D8C0 holds M (p2 module) at +0x00 and R (RIP module) at +0x40 with a
# UNICODE_STRING name. Print the surrounding record array (bases + strides) and all name strings,
# so record index <-> name index can be aligned. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bx_recs.txt'
Set-Content -LiteralPath $out -Value ('p269bx ' + (Get-Date -f 'HH:mm:ss'))
$b = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$p2 = [BitConverter]::ToUInt64($b, 0x48); $M = $p2 - 0x5B8
$R = [BitConverter]::ToUInt64($b, 0x440) - 0x660
Add-Content -LiteralPath $out -Value ('M=0x{0:X}  R=0x{1:X}' -f $M, $R)
Add-Content -LiteralPath $out -Value '-- page-aligned kernel bases 0x10000..0x40000 --'
$LO = [BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]::MinValue), 0)   # 0x8000000000000000
$prev = -1
for ($i = 0x10000; $i -lt 0x40000; $i += 8) {
    $v = [BitConverter]::ToUInt64($b, $i)
    if ($v -lt $LO) { continue }
    if (($v -shr 40) -ne 0xFFFFF8) { continue }
    if (($v -band 0xFFF) -ne 0) { continue }
    $st = '     '
    if ($prev -ge 0) { $st = 'stride=' + ($i - $prev) }
    $t = ''
    if ($v -eq $M) { $t = ' <=M' } elseif ($v -eq $R) { $t = ' <=R' }
    Add-Content -LiteralPath $out -Value ('  @0x{0:X5} 0x{1:X16} {2}{3}' -f $i, $v, $st, $t)
    $prev = $i
}
Add-Content -LiteralPath $out -Value 'END'
