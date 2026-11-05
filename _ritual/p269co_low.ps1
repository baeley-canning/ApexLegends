# p269co: inspect the record that sits just below RIP (rec 0x11058) — is it a module record, and what name does it carry?
# Also read the bugcheck header params for context. Read-only.
$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269co_low.txt'
$o = @('p269co')
$o += ('hdr code=0x{0:X} p1=0x{1:X} p2=0x{2:X} p3=0x{3:X} p4=0x{4:X} rip=0x{5:X} p2off=0x{6:X}' -f ([BitConverter]::ToUInt32($buf, 0x38)), ([BitConverter]::ToUInt64($buf, 0x40)), ([BitConverter]::ToUInt64($buf, 0x48)), ([BitConverter]::ToUInt64($buf, 0x50)), ([BitConverter]::ToUInt64($buf, 0x58)), ([BitConverter]::ToUInt64($buf, 0x440)), ([BitConverter]::ToUInt64($buf, 0x08)))
foreach ($win in @(@(0x11030, 0x11110))) {
    $o += ('-- {0:X5}..{1:X5}' -f $win[0], $win[1])
    for ($i = $win[0]; $i -lt $win[1]; $i += 16) {
        $s = '{0:X5} ' -f $i; $a = ''
        for ($j = 0; $j -lt 16; $j++) { $c = $buf[$i + $j]; $s += '{0:X2} ' -f $c; $a += $(if ($c -ge 32 -and $c -lt 127) { [char]$c } else { '.' }) }
        $o += ($s + ' ' + $a)
    }
}
# try name refs on a window of candidate record starts
foreach ($rec in @(0x11030, 0x11038, 0x11040, 0x11048, 0x11050, 0x11058, 0x11060, 0x11068, 0x11070)) {
    $base = [BitConverter]::ToUInt64($buf, $rec)
    $q = [BitConverter]::ToUInt64($buf, $rec + 0x58)
    $ln = [BitConverter]::ToUInt32($buf, $rec + 0x58)
    $sz = [BitConverter]::ToUInt32($buf, $rec + 0x10)
    $o += ('rec=0x{0:X5} base=0x{1:X} size=0x{2:X} nameField=0x{3:X} nameLenIfInline=0x{4:X}' -f $rec, $base, $sz, $q, $ln)
}
Set-Content -LiteralPath $out -Value $o
