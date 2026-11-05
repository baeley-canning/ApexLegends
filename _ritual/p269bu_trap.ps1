# p269bu: 0x3B p2 is the faulting DATA address; the code address is Rip in the trap frame (p3).
# Dump the trap frame window of every dump and flag pointers whose low 12 bits are 0x5B8/0xB8.
# Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bu_trap.txt'
Set-Content -LiteralPath $out -Value ('p269bu ' + (Get-Date -f 'HH:mm:ss'))
function MapPut([byte[]]$b, [uint64]$va) {
    $h = New-Object byte[] 0x2000
    [Array]::Copy($b, 0, $h, 0, 0x2000)
    $off = [BitConverter]::ToUInt64($h, 0x1000)          # KdDebuggerDataBlock style? fallback below
    return $off
}
foreach ($d in (Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp)) {
    $b = [IO.File]::ReadAllBytes($d.FullName)
    $code = [BitConverter]::ToUInt32($b, 0x38)
    $p1 = [BitConverter]::ToUInt64($b, 0x40); $p2 = [BitConverter]::ToUInt64($b, 0x48)
    $p3 = [BitConverter]::ToUInt64($b, 0x50); $p4 = [BitConverter]::ToUInt64($b, 0x58)
    Add-Content -LiteralPath $out -Value ('== {0} code=0x{1:X} p1=0x{2:X} p2=0x{3:X} p3=0x{4:X} p4=0x{5:X}' -f $d.Name, $code, $p1, $p2, $p3, $p4)
    if ($p3 -eq 0) { Add-Content -LiteralPath $out -Value '  p3 empty'; continue }
    $page = $p3 -band 0xFFFFFFFFFFFFF000
    $name2 = [Text.Encoding]::GetEncoding(28591)
    $hay = $name2.GetString($b)
    $needle = $name2.GetString([BitConverter]::GetBytes([uint64]$page))
    $pos = $hay.IndexOf($needle)
    Add-Content -LiteralPath $out -Value ('  p3page=0x{0:X} presentAt=0x{1:X} (delta 0x{2:X})' -f $page, $pos, ($p3 - $page))
    if ($pos -lt 0) { continue }
    for ($k = 0x30; $k -lt 0x120; $k += 8) {
        $v = [BitConverter]::ToUInt64($b, $pos + ($p3 - $page) + $k)
        $mark = ''
        if (($v -band 0xFFF) -eq 0x5B8) { $mark = '  <== low12=5B8' }
        Add-Content -LiteralPath $out -Value ('   tf+0x{0:X3} 0x{1:X16}{2}' -f $k, $v, $mark)
    }
}
Add-Content -LiteralPath $out -Value 'END'
