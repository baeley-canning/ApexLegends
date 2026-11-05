# p269cm: layout-correct record walk, no stride assumption.
# rec+0x00 base (8-aligned, 0x1000-aligned), rec+0x10 SizeOfImage (page-multiple),
# rec+0x58 name ref: either inline length dword at +0x58 (text at +0x5C) or qword ptr -> length dword -> text.
# Resolve DATA (p2-0x15B8) and CODE (RIP-0x660) by containment. Read-only.
$dir = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cm_table.txt'
Set-Content -LiteralPath $out -Value ('p269cm ' + (Get-Date -f 'HH:mm:ss'))
function Sub([uint64]$v, [int]$d) {
    $i = [BitConverter]::ToInt64([BitConverter]::GetBytes($v), 0) - $d
    return [BitConverter]::ToUInt64([BitConverter]::GetBytes($i), 0)
}
function Try-Text([byte[]]$buf, [int64]$lenAt, [int64]$txtAt) {
    if ($lenAt -lt 0 -or $txtAt -lt 0 -or ($txtAt + 2) -ge $buf.Length) { return '' }
    $len = [BitConverter]::ToUInt32($buf, [int]$lenAt)
    if ($len -lt 6 -or $len -gt 0x400) { return '' }
    $sb = New-Object Text.StringBuilder
    for ($k = 0; $k -lt $len; $k++) {
        $ch = [BitConverter]::ToUInt16($buf, [int]$txtAt + $k * 2)
        if ($ch -lt 0x20 -or $ch -gt 0x7E) { return '' }
        [void]$sb.Append([char]$ch)
    }
    return $sb.ToString()
}
function Get-Name([byte[]]$buf, [int64]$rec) {
    $inl = Try-Text $buf ($rec + 0x58) ($rec + 0x5C)
    if ($inl -ne '' -and $inl.IndexOf('.') -gt 0) { return ('inl:' + $inl) }
    $pt = [BitConverter]::ToUInt64($buf, [int]$rec + 0x58)
    if ($pt -lt 0x10000 -or $pt -ge $buf.Length) { return '' }
    $ref = Try-Text $buf $pt ($pt + 4)
    if ($ref -ne '' -and $ref.IndexOf('.') -gt 0) { return ('ref:' + $ref) }
    return ''
}
foreach ($d in (Get-ChildItem -LiteralPath $dir -Filter *.dmp | Sort-Object Name)) {
    $buf = [IO.File]::ReadAllBytes($d.FullName)
    $p2 = [BitConverter]::ToUInt64($buf, 0x48)
    $rip = [BitConverter]::ToUInt64($buf, 0x440)
    $tData = Sub $p2 0x15B8
    $tCode = Sub $rip 0x660
    Add-Content -LiteralPath $out -Value ('== {0} p2=0x{1:X} data=0x{2:X} code=0x{3:X}' -f $d.Name, $p2, $tData, $tCode)
    $tbl = New-Object System.Collections.ArrayList
    for ($rec = 0x10000; $rec -lt 0x1C000; $rec += 8) {
        $base = [BitConverter]::ToUInt64($buf, $rec)
        if ((($base -shr 40) -band 0xFF) -ne 0xF8) { continue }
        if (($base -band 0xFFF) -ne 0) { continue }
        $sz = [BitConverter]::ToUInt32($buf, $rec + 0x10)
        if ($sz -eq 0 -or $sz -gt 0x1000000 -or ($sz -band 0xFFF) -ne 0) { continue }
        $nm = Get-Name $buf $rec
        if ($nm -eq '') { continue }
        [void]$tbl.Add([pscustomobject]@{ Off = $rec; Base = $base; Size = $sz; Name = $nm })
    }
    $i = 0
    foreach ($e in $tbl) { Add-Content -LiteralPath $out -Value ('  idx={0} rec=0x{1:X5} base=0x{2:X} size=0x{3:X} {4}' -f $i, $e.Off, $e.Base, $e.Size, $e.Name); $i++ }
    Add-Content -LiteralPath $out -Value ('  entries={0}' -f $tbl.Count)
    foreach ($t in @(@('DATA', $tData), @('CODE', $tCode))) {
        $tag = $t[0]; $addr = [uint64]$t[1]
        $hit = @($tbl | Where-Object { $addr -ge $_.Base -and $addr -lt ($_.Base + [uint64]$_.Size) })
        if ($hit.Count -gt 0) {
            Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X} -> OWNER rec=0x{2:X5} base=0x{3:X} +0x{4:X} size=0x{5:X} {6}' -f $tag, $addr, $hit[0].Off, $hit[0].Base, ($addr - $hit[0].Base), $hit[0].Size, $hit[0].Name)
        } else {
            Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X} -> NO OWNER in table' -f $tag, $addr)
        }
    }
}
Add-Content -LiteralPath $out -Value 'END'
