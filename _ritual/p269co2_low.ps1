$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269co_low.txt'
Set-Content -LiteralPath $out -Value @('p269co2')
for ($i = 0x11020; $i -lt 0x11120; $i += 16) {
    $s = '{0:X5} ' -f $i; $a = ''
    for ($j = 0; $j -lt 16; $j++) { $c = $buf[$i + $j]; $s += '{0:X2} ' -f $c; $a += $(if ($c -ge 32 -and $c -lt 127) { [char]$c } else { '.' }) }
    Add-Content -LiteralPath $out -Value ($s + ' ' + $a)
}
