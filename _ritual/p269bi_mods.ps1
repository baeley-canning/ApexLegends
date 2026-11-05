# p269bi: identify the module behind a fixed fault offset. The bugcheck param2 in all
# five dumps ends in 0x5B8, so only the image base changes run to run. Walk the minidump
# ModuleList (stream type 4) and report which image owns param2-0x5B8.
# Read-only: writes nothing but the report file.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bi_mods.txt'
Set-Content -LiteralPath $out -Value ('p269bi ' + (Get-Date -f 'HH:mm:ss'))

function U32([byte[]]$b, [int]$o) { [BitConverter]::ToUInt32($b, $o) }
function U64([byte[]]$b, [int]$o) { [BitConverter]::ToUInt64($b, $o) }

foreach ($f in Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $code = U32 $b 0x38; $p2 = U64 $b 0x40
    $fault = U64 $b 0x40
    Add-Content -LiteralPath $out -Value ('== ' + $f.Name + ' code=0x' + $code.ToString('X8'))
    $dirCount = U32 $b 0x08; $dirRva = U32 $b 0x0C
    $modStream = $null
    for ($i = 0; $i -lt $dirCount; $i++) {
        $e = $dirRva + ($i * 12)
        if ((U32 $b $e) -eq 4) { $modStream = $e }
    }
    if (-not $modStream) { Add-Content -LiteralPath $out -Value '  (no module list stream)'; continue }
    $size = U32 $b ($modStream + 4); $rva = U32 $b ($modStream + 8)
    $n = U32 $b $rva
    Add-Content -LiteralPath $out -Value ('  modules=' + $n)
    $hit = $null
    for ($j = 0; $j -lt $n; $j++) {
        $me = $rva + 4 + ($j * 108)
        if ($me + 108 -gt $b.Length) { break }
        $base = U64 $b $me
        $imgSize = U32 $b ($me + 8)
        $nameRva = U32 $b ($me + 104)
        if ($nameRva -le 0 -or $nameRva + 4 -gt $b.Length) { continue }
        $cch = U32 $b $nameRva
        $name = [Text.Encoding]::Unicode.GetString($b, $nameRva + 4, [Math]::Min($cch * 2, 260))
        if ($fault -ge $base -and $fault -lt ($base + $imgSize)) {
            $hit = ('{0} base=0x{1:X} size=0x{2:X} off=0x{3:X}' -f $name, $base, $imgSize, ($fault - $base))
        }
    }
    if ($hit) { Add-Content -LiteralPath $out -Value ('  FAULT IN: ' + $hit) }
    else { Add-Content -LiteralPath $out -Value ('  fault 0x' + $fault.ToString('X') + ' not inside any listed image') }
    # drivers only, to keep the report short
    for ($j = 0; $j -lt $n; $j++) {
        $me = $rva + 4 + ($j * 108)
        if ($me + 108 -gt $b.Length) { break }
        $nameRva = U32 $b ($me + 104)
        if ($nameRva -le 0 -or $nameRva + 4 -gt $b.Length) { continue }
        $cch = U32 $b $nameRva
        $name = [Text.Encoding]::Unicode.GetString($b, $nameRva + 4, [Math]::Min($cch * 2, 260))
        if ($name -match 'apex|kdu|vbox') { Add-Content -LiteralPath $out -Value ('  drv ' + $name + ' base=0x' + (U64 $b $me).ToString('X')) }
    }
}
Add-Content -LiteralPath $out -Value 'END'
