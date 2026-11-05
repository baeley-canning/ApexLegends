# p269ck: exercise p269cj's name resolution path on the known-good record 0x18430. Read-only.
$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269ck_diag.txt'
$o = @('p269ck')
$rec = 0x18430
$base = [BitConverter]::ToUInt64($buf, $rec)
$o += ('base=0x{0:X} shr40=0x{1:X} band=0x{2:X} pass={3}' -f $base, ($base -shr 40), (($base -shr 40) -band 0xFF), ((($base -shr 40) -band 0xFF) -eq 0xF8))
$o += ('inlineLenAt0x{0:X5}=0x{1:X}' -f ($rec + 0x60), ([BitConverter]::ToUInt32($buf, $rec + 0x60)))
$pt = [BitConverter]::ToUInt64($buf, $rec + 0x60)
$o += ('ptr=0x{0:X}' -f $pt)
$len = [BitConverter]::ToUInt32($buf, [int]$pt)
$sb = New-Object Text.StringBuilder
for ($k = 0; $k -lt [math]::Min($len, 0x80); $k++) { [void]$sb.Append([char][BitConverter]::ToUInt16($buf, [int]$pt + 4 + $k * 2)) }
$o += ('ptrLen=0x{0:X} text="{1}"' -f $len, $sb.ToString())
$sz = [BitConverter]::ToUInt32($buf, $rec + 0x10)
$o += ('size=0x{0:X} sizeOk={1}' -f $sz, ($sz -le 0x4000000))
$n = 0; $al = 0
for ($r = 0x10000; $r -lt 0x1B000; $r += 8) {
    $bb = [BitConverter]::ToUInt64($buf, $r)
    if ((($bb -shr 40) -band 0xFF) -ne 0xF8) { continue }
    $n++
    if (($bb -band 0xFFF) -ne 0) { continue }
    $al++
}
$o += ('step8 F8pass={0} aligned={1}' -f $n, $al)
Set-Content -LiteralPath $out -Value $o
