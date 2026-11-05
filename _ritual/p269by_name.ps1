# p269by: index 174 (0-based) in the module table at 0x12408 (stride 0x90) = 0xFFFFF80452220000,
# i.e. the base for the faulting read p2-0x15B8. Name blob 0xC3E2..0xE1C6 is the parallel name array;
# print names by index, plus the count of both arrays. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269by_name.txt'
Set-Content -LiteralPath $out -Value ('p269by ' + (Get-Date -f 'HH:mm:ss'))
$b = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$names = New-Object System.Collections.ArrayList
$sb = New-Object Text.StringBuilder
for ($i = 0xC3E2; $i -lt 0xE1D0; $i += 2) {
    $ch = [BitConverter]::ToUInt16($b, $i)
    if ($ch -eq 0) { if ($sb.Length -gt 2) { [void]$names.Add($sb.ToString()) }; [void]$sb.Clear() }
    elseif ($ch -ge 0x20 -and $ch -lt 0xD800) { [void]$sb.Append([char]$ch) }
    else { [void]$sb.Append('?') }
}
$recStart = 0x12408; $stride = 0x90
$count = 0
while (($recStart + $count * $stride + 8) -lt 0x40000) {
    $v = [BitConverter]::ToUInt64($b, $recStart + $count * $stride + 0x40)
    if ($v -eq 0) { break }
    $count++
}
Add-Content -LiteralPath $out -Value ('names={0} records(0x90 stride, +0x40 nonnull)={1}' -f $names.Count, $count)
for ($n = 168; $n -lt [Math]::Min(182, $names.Count); $n++) { Add-Content -LiteralPath $out -Value ('  [{0}] {1}' -f $n, $names[$n]) }
Add-Content -LiteralPath $out -Value '-- all names --'
for ($n = 0; $n -lt $names.Count; $n++) { Add-Content -LiteralPath $out -Value ('  [{0}] {1}' -f $n, $names[$n]) }
Add-Content -LiteralPath $out -Value 'END'
