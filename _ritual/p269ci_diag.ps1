# p269ci: diagnostic — why does the record walk find nothing? Print raw decode at known-good recs. Read-only.
$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269ci_diag.txt'
$o = @('p269ci')
foreach ($rec in @(0x18432, 0x184C2, 0x1855A)) {
    $base = [BitConverter]::ToUInt64($buf, $rec + 2)
    $pt = [BitConverter]::ToUInt64($buf, $rec + 0x5E)
    $len = [BitConverter]::ToUInt32($buf, [int]$pt)
    $sb = New-Object Text.StringBuilder
    for ($k = 0; $k -lt [math]::Min($len, 0x80); $k++) { [void]$sb.Append([char][BitConverter]::ToUInt16($buf, [int]$pt + 4 + $k * 2)) }
    $o += ('rec=0x{0:X5} base=0x{1:X} shr40={2:X} bandFF={3:X} ptr=0x{4:X} len=0x{5:X} s="{6}"' -f $rec, $base, ($base -shr 40), (($base -shr 40) -band 0xFF), $pt, $len, $sb.ToString())
}
$pass = 0; $ptr = 0; $str = 0
for ($rec = 0x10000; $rec -lt 0x1F000; $rec += 2) {
    $base = [BitConverter]::ToUInt64($buf, $rec + 2)
    if ((($base -shr 40) -band 0xFF) -ne 0xF8) { continue }
    $pass++
    if (($base -band 0xFFF) -ne 0) { continue }
    $ptr++
}
$o += ('base-filter pass={0} aligned={1}' -f $pass, $ptr)
Set-Content -LiteralPath $out -Value $o
