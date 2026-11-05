# p269bv: find code pointers (0xFFFFF800'00000000-0xFFFFF8FF'FFFFFFFF) anywhere in the trap-frame
# page and report their low-12 offsets. A constant low-12 across dumps = the faulting call site.
# Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bv_codes.txt'
Set-Content -LiteralPath $out -Value ('p269bv ' + (Get-Date -f 'HH:mm:ss'))
$enc = [Text.Encoding]::GetEncoding(28591)
foreach ($d in (Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp)) {
    $b = [IO.File]::ReadAllBytes($d.FullName)
    $p2 = [BitConverter]::ToUInt64($b, 0x48); $p3 = [BitConverter]::ToUInt64($b, 0x50)
    Add-Content -LiteralPath $out -Value ('== {0} p2=0x{1:X} p3=0x{2:X} p2base=0x{3:X}' -f $d.Name, $p2, $p3, ($p2 - 0x5B8))
    $page = $p3 -band 0xFFFFFFFFFFFFF000
    $pos = $enc.GetString($b).IndexOf($enc.GetString([BitConverter]::GetBytes([uint64]$page)))
    if ($pos -lt 0) { Add-Content -LiteralPath $out -Value '  page absent'; continue }
    $start = $pos + ($p3 - $page) - 0xB00
    for ($k = 0; $k -lt 0x1000; $k += 8) {
        $v = [BitConverter]::ToUInt64($b, $start + $k)
        if ($v -lt 0xFFFFF80000000000 -or $v -gt 0xFFFFF8FFFFFFFFFF) { continue }
        if (($v -band 0xFFF) -eq 0) { continue }
        $rel = $v - ($p2 - 0x5B8)
        Add-Content -LiteralPath $out -Value ('   @0x{0:X3} 0x{1:X16} low12=0x{2:X3} relToP2base={3}' -f $k, $v, ($v -band 0xFFF), $(if ($rel -ge 0 -and $rel -lt 0x10000) { '0x' + $rel.ToString('X') } else { '-' }))
    }
}
Add-Content -LiteralPath $out -Value 'END'
