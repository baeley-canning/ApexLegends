# p269bz: locate every UTF-16 module name in the dump (`.sys` pattern), decode the enclosing string,
# and print them in file order with an index so record index <-> name index can be compared. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bz_names.txt'
Set-Content -LiteralPath $out -Value ('p269bz ' + (Get-Date -f 'HH:mm:ss'))
$b = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$enc = [Text.Encoding]::GetEncoding(28591)
$hay = $enc.GetString($b)
$pat = $enc.GetString([byte[]](0x2E, 0, 0x73, 0, 0x79, 0x73))
$p = 0; $n = 0
while (($p = $hay.IndexOf($pat, $p)) -ge 0) {
    $s = $p - 2
    while ($s -gt 2 -and ([BitConverter]::ToUInt16($b, $s - 2) -ge 0x20)) { $s -= 2 }
    $t = $s
    $sb = New-Object Text.StringBuilder
    while ($t -lt $b.Length - 1 -and [BitConverter]::ToUInt16($b, $t) -ne 0) { [void]$sb.Append([char][BitConverter]::ToUInt16($b, $t)); $t += 2 }
    Add-Content -LiteralPath $out -Value ('[{0}] @0x{1:X} {2}' -f $n, $s, $sb.ToString())
    $n++; $p += 6
}
Add-Content -LiteralPath $out -Value ('TOTAL=' + $n)
Add-Content -LiteralPath $out -Value 'END'
