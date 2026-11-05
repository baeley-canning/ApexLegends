# Confirm the resolver's off-by-index: functions[nameIndex] vs functions[ordinal].
$ErrorActionPreference = 'Stop'
$o = Join-Path $PSScriptRoot '_exp_check2.txt'
$b = [IO.File]::ReadAllBytes((Join-Path $env:SystemRoot 'System32\kernelbase.dll'))
function U32([int]$off) { [BitConverter]::ToUInt32($b, $off) }
$nt = U32 0x3C
$dirRva = U32 ($nt + 0x18 + 0x70)
$funcs = U32 ($dirRva + 0x1C)
foreach ($i in 1070..1080) {
    ('functions[{0}] = 0x{1:X}' -f $i, (U32 ($funcs + $i * 4))) | Out-File $o -Append -Encoding utf8
}
'driver reported 0xFC5B0 ; real LoadLibraryW = 0xFC6D0 (nameIndex 1073, ordinal 1076)' | Out-File $o -Append -Encoding utf8
Get-Content $o
