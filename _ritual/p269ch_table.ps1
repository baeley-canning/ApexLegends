# p269ch: build the real base<->path table. Record layout observed: base qword at rec+0x02,
# SizeOfImage dword at rec+0x16, path-pointer qword at rec+0x5E (points at UTF-16 path, length dword at ptr-4).
# Print the table, then resolve the two fault addresses to their owning records. Read-only.
# NB: the byte array is $buf, never $b, because $B (offset) collides case-insensitively.
$dir = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269ch_table.txt'
Set-Content -LiteralPath $out -Value ('p269ch ' + (Get-Date -f 'HH:mm:ss'))
function Sub([uint64]$v, [int]$d) {
    $i = [BitConverter]::ToInt64([BitConverter]::GetBytes($v), 0) - $d
    return [BitConverter]::ToUInt64([BitConverter]::GetBytes($i), 0)
}
function Read-Str([byte[]]$buf, [int64]$pt) {
    if ($pt -lt 4 -or $pt -ge ($buf.Length - 8)) { return '' }
    $len = [BitConverter]::ToUInt32($buf, [int]$pt)
    if ($len -lt 6 -or $len -gt 0x400) { return '' }
    $sb = New-Object Text.StringBuilder
    for ($k = 0; $k -lt $len; $k++) {
        $ch = [BitConverter]::ToUInt16($buf, [int]$pt + 4 + $k * 2)
        if ($ch -lt 0x20 -or $ch -gt 0x7E) { return '' }
        [void]$sb.Append([char]$ch)
    }
    $s = $sb.ToString()
    if ($s.IndexOf('.') -lt 0) { return '' }
    return $s
}foreach ($d in (Get-ChildItem -LiteralPath $dir -Filter *.dmp | Sort-Object Name)) {
    $buf = [IO.File]::ReadAllBytes($d.FullName)
    $p2 = [BitConverter]::ToUInt64($buf, 0x48)
    $rip = [BitConverter]::ToUInt64($buf, 0x440)
    $tData = Sub $p2 0x15B8
    $tCode = Sub $rip 0x660
    Add-Content -LiteralPath $out -Value ('== {0} p2=0x{1:X} data=0x{2:X} code=0x{3:X}' -f $d.Name, $p2, $tData, $tCode)
    $tbl = New-Object System.Collections.ArrayList
    for ($rec = 0x10000; $rec -lt 0x1F000; $rec += 2) {
        $base = [BitConverter]::ToUInt64($buf, $rec + 2)
        if ((($base -shr 40) -band 0xFF) -ne 0xF8) { continue }
        if (($base -band 0xFFF) -ne 0) { continue }
        $pt = [BitConverter]::ToUInt64($buf, $rec + 0x5E)
        if ($pt -lt 0x10000 -or $pt -ge $buf.Length) { continue }
        $nm = Read-Str $buf $pt
        if ($nm -eq '') { continue }
        $sz = [BitConverter]::ToUInt32($buf, $rec + 0x16)
        [void]$tbl.Add([pscustomobject]@{ Off = $rec; Base = $base; Size = $sz; Name = $nm })
        Add-Content -LiteralPath $out -Value ('  rec=0x{0:X5} base=0x{1:X} size=0x{2:X} {3}' -f $rec, $base, $sz, $nm)
    }
    Add-Content -LiteralPath $out -Value ('  entries={0}' -f $tbl.Count)
    foreach ($t in @(@('DATA', $tData), @('CODE', $tCode))) {
        $tag = $t[0]; $addr = [uint64]$t[1]
        $owner = @($tbl | Where-Object { $_.Base -eq $addr })
        if ($owner.Count -gt 0) {
            Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X} -> OWNER rec=0x{2:X5} size=0x{3:X} {4}' -f $tag, $addr, $owner[0].Off, $owner[0].Size, $owner[0].Name)
        } else {
            Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X} -> no record with this base' -f $tag, $addr)
        }
    }
}
Add-Content -LiteralPath $out -Value 'END'
