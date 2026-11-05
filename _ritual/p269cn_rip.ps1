# p269cn: raw-RIP containment + tail of the module table. Read-only.
$dir = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cn_rip.txt'
Set-Content -LiteralPath $out -Value 'p269cn'
foreach ($d in (Get-ChildItem -LiteralPath $dir -Filter *.dmp | Sort-Object Name)) {
    $buf = [IO.File]::ReadAllBytes($d.FullName)
    $rip = [BitConverter]::ToUInt64($buf, 0x440)
    $hits = @()
    for ($rec = 0x10000; $rec -lt 0x1C000; $rec += 8) {
        $base = [BitConverter]::ToUInt64($buf, $rec)
        if ((($base -shr 40) -band 0xFF) -ne 0xF8) { continue }
        if (($base -band 0xFFF) -ne 0) { continue }
        $sz = [BitConverter]::ToUInt32($buf, $rec + 0x10)
        if ($sz -eq 0 -or $sz -gt 0x1000000) { continue }
        if ($rip -ge $base -and $rip -lt ($base + [uint64]$sz)) {
            $hits += ('rec=0x{0:X5} base=0x{1:X} +0x{2:X} size=0x{3:X}' -f $rec, $base, ($rip - $base), $sz)
        }
    }
    Add-Content -LiteralPath $out -Value ('== {0} rip=0x{1:X} containing={2}' -f $d.Name, $rip, $hits.Count)
    foreach ($h in $hits) { Add-Content -LiteralPath $out -Value ('   {0}' -f $h) }
    # nearest record base below rip
    $near = 0; $nbase = [uint64]0
    for ($rec = 0x10000; $rec -lt 0x1C000; $rec += 8) {
        $base = [BitConverter]::ToUInt64($buf, $rec)
        if ((($base -shr 40) -band 0xFF) -ne 0xF8) { continue }
        if ($base -le $rip -and $base -gt $nbase) { $nbase = $base; $near = $rec }
    }
    if ($near -ne 0) { Add-Content -LiteralPath $out -Value ('   nearest base below rip: rec=0x{0:X5} base=0x{1:X} delta=0x{2:X}' -f $near, $nbase, ($rip - $nbase)) }
}
