# p269br: validate that the p2-0x5B8 qword hit is a KLDR_DATA_TABLE_ENTRY
# (SizeOfImage at +0x40, UNICODE_STRING at +0x48) and locate the UTF-16 driver name.
# Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269br_entry.txt'
Set-Content -LiteralPath $out -Value ('p269br ' + (Get-Date -f 'HH:mm:ss'))
$b = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$p2 = [BitConverter]::ToUInt64($b, 0x48); $base = $p2 - 0x5B8
$pat = [BitConverter]::GetBytes($base)
$hit = -1
for ($i = 0; $i -lt ($b.Length - 8); $i++) { if ($b[$i] -eq $pat[0] -and [BitConverter]::ToUInt64($b, $i) -eq $base) { $hit = $i; break } }
Add-Content -LiteralPath $out -Value ('p2=0x' + $p2.ToString('X') + ' base=0x' + $base.ToString('X') + ' hit=0x' + $hit.ToString('X'))
if ($hit -lt 0) { Add-Content -LiteralPath $out -Value 'no hit'; exit }
Add-Content -LiteralPath $out -Value ('entryStart(=hit-0x30)=0x' + ($hit - 0x30).ToString('X'))
for ($k = -0x30; $k -le 0x70; $k += 8) {
    $v = [BitConverter]::ToUInt64($b, $hit + $k)
    Add-Content -LiteralPath $out -Value ('  +{0,-4:X3} 0x{1:X16}' -f $k, $v)
}
# unicode strings in the whole dump containing 'drv' or '.sys'
$u = [Text.Encoding]::Unicode.GetString($b)
foreach ($m in [regex]::Matches($u, '[\x20-\x7E]{4,80}\.(sys|SYS)')) {
    Add-Content -LiteralPath $out -Value ('  str@0x' + ($m.Index * 1).ToString('X') + ' ' + $m.Value)
}
foreach ($m in [regex]::Matches($u, '[A-Za-z]{3,20}drv[A-Za-z0-9_]{0,10}')) {
    Add-Content -LiteralPath $out -Value ('  drvstr charpos=0x' + $m.Index.ToString('X') + ' ' + $m.Value)
}
Add-Content -LiteralPath $out -Value 'END'
