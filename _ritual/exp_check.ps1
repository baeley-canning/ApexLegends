# Is kernelbase!LoadLibraryW real code, or a forwarder string?
# A forwarded export's "RVA" points INTO the export directory, i.e. at a string
# ("KERNEL32.Something"), not at code. Executing that address is the same as calling
# a data blob. Pure read of the on-disk image, no driver, no VM.
$ErrorActionPreference = 'Stop'
$o = Join-Path $PSScriptRoot '_exp_check.txt'
$p = Join-Path $env:SystemRoot 'System32\kernelbase.dll'
$b = [IO.File]::ReadAllBytes($p)
function U32([int]$off) { return [BitConverter]::ToUInt32($b, $off) }
function U16([int]$off) { return [BitConverter]::ToUInt16($b, $off) }
$nt = U32 0x3C
$dirRva = U32 ($nt + 0x18 + 0x70)
$dirSize = U32 ($nt + 0x18 + 0x74)
$numNames = U32 ($dirRva + 0x18)
$names = U32 ($dirRva + 0x20)
$ords = U32 ($dirRva + 0x24)
$funcs = U32 ($dirRva + 0x1C)
$numFuncs = U32 ($dirRva + 0x14)
$hit = -1
for ($i = 0; $i -lt $numNames; $i++) {
    $nr = U32 ($names + $i * 4)
    $end = $nr
    while ($b[$end] -ne 0) { $end++ }
    $name = [Text.Encoding]::ASCII.GetString($b, $nr, $end - $nr)
    if ($name -eq 'LoadLibraryW') { $hit = $i; break }
}
"kernelbase=$p len=$($b.Length)" | Out-File $o -Encoding utf8
"exportdir rva=0x{0:X} size=0x{1:X} names=$numNames funcs=$numFuncs" -f $dirRva, $dirSize | Out-File $o -Append -Encoding utf8
if ($hit -lt 0) { 'LoadLibraryW NOT FOUND in kernelbase exports' | Out-File $o -Append -Encoding utf8 }
else {
    $ord = U16 ($ords + $hit * 2)
    $rva = U32 ($funcs + $ord * 4)
    $forwarded = ($rva -ge $dirRva -and $rva -lt ($dirRva + $dirSize))
    "LoadLibraryW: nameIndex=$hit ordinal=$ord rva=0x{0:X} forwarded=$forwarded" -f $rva | Out-File $o -Append -Encoding utf8
    if ($forwarded) {
        $e = $rva
        while ($b[$e] -ne 0) { $e++ }
        'FORWARDER -> ' + [Text.Encoding]::ASCII.GetString($b, $rva, $e - $rva) | Out-File $o -Append -Encoding utf8
    }
}
Get-Content $o
