# p269cl: hexdump the record neighbourhood around the likely zapexdrv record, byte-exact. Read-only.
$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cl_hex.txt'
$o = @('p269cl')
foreach ($win in @(@(0x18420, 0x184C0), @(0x185C0, 0x18660))) {
    $o += ('-- {0:X5}..{1:X5}' -f $win[0], $win[1])
    for ($i = $win[0]; $i -lt $win[1]; $i += 16) {
        $s = '{0:X5} ' -f $i; $a = ''
        for ($j = 0; $j -lt 16; $j++) { $c = $buf[$i + $j]; $s += '{0:X2} ' -f $c; $a += $(if ($c -ge 32 -and $c -lt 127) { [char]$c } else { '.' }) }
        $o += ($s + ' ' + $a)
    }
}
Set-Content -LiteralPath $out -Value $o
