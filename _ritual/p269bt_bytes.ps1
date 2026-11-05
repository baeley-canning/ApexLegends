# p269bt: the faulting instruction page is often captured in a small dump. Take 24 actual
# bytes from each candidate at the suspect RVA and search all five dumps for them.
# A unique hit names the module. Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bt_bytes.txt'
Set-Content -LiteralPath $out -Value ('p269bt ' + (Get-Date -f 'HH:mm:ss'))
$cands = @(
    @{ n = 'zapexdrv@5B8';  f = 'C:\p37vm\payload\zapexdrv.sys';    raw = 0x400;  va = 0x1000 },
    @{ n = 'zapexdrv@15B8'; f = 'C:\p37vm\payload\zapexdrv.sys';    raw = 0x400;  va = 0x1000 },
    @{ n = 'gdrv3@5B8';     f = 'C:\p37vm\payload\gdrv3.sys';       raw = 0x400;  va = 0x1000 },
    @{ n = 'DBUtilDrv2@5B8';f = 'C:\p37vm\payload\DBUtilDrv2.sys';  raw = 0x400;  va = 0x1000 },
    @{ n = 'apexdrv_unsigned@5B8'; f = 'C:\p37vm\payload\apexdrv.sys'; raw = 0x400; va = 0x1000 }
)
$dumps = Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp
foreach ($c in $cands) {
    if (-not (Test-Path -LiteralPath $c.f)) { Add-Content -LiteralPath $out -Value ($c.n + ' MISSING'); continue }
    $fb = [IO.File]::ReadAllBytes($c.f)
    $eL = [BitConverter]::ToInt32($fb, 0x3C)
    $nSec = [BitConverter]::ToUInt16($fb, $eL + 6)
    $secBase = $eL + 24 + [BitConverter]::ToUInt16($fb, $eL + 20)
    # resolve the raw file offset of the requested RVA from the section table
    $rva = [Convert]::ToInt32(($c.n -split '@')[1], 16)
    $off = -1
    for ($i = 0; $i -lt $nSec; $i++) {
        $o = $secBase + ($i * 40)
        $vad = [BitConverter]::ToUInt32($fb, $o + 12); $vsz = [BitConverter]::ToUInt32($fb, $o + 8)
        $rad = [BitConverter]::ToUInt32($fb, $o + 20)
        if ($rva -ge $vad -and $rva -lt ($vad + $vsz)) { $off = $rad + ($rva - $vad) }
    }
    if ($off -lt 0 -and $rva -lt 0x400) { $off = $rva }   # RVA inside the PE headers maps 1:1
    if ($off -lt 0) { Add-Content -LiteralPath $out -Value ('{0} rva 0x{1:X} not in any section' -f $c.n, $rva); continue }
    $pat = $fb[$off..($off + 23)]
    Add-Content -LiteralPath $out -Value ('{0} rva=0x{1:X} pat=' -f $c.n, $rva + (($pat | ForEach-Object { $_.ToString('X2') }) -join ' '))
    foreach ($d in $dumps) {
        $b = [IO.File]::ReadAllBytes($d.FullName)
        $enc = [Text.Encoding]::GetEncoding(28591)
        $hay = $enc.GetString($b)
        $needle = $enc.GetString($pat)
        $hits = 0; $first = -1; $p = 0
        while ($true) {
            $x = $hay.IndexOf($needle, $p)
            if ($x -lt 0) { break }
            $hits++; if ($first -lt 0) { $first = $x }
            $p = $x + 1
        }
        if ($hits) { Add-Content -LiteralPath $out -Value ('   {0} hits={1} first=0x{2:X}' -f $d.Name, $hits, $first) }
    }
}
Add-Content -LiteralPath $out -Value 'END'
